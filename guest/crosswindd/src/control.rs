// SPDX-License-Identifier: AGPL-3.0-or-later
//! Control channel: answers host requests (Flatpak management, app launch) over a second vsock link.
//!
//! Blocking Flatpak work runs on worker threads. Those threads, and the child-process watchers,
//! report back through a calloop channel of `Note`s, so all link writes happen on the loop thread.

use std::{
    collections::HashMap,
    io::{self, BufRead, BufReader, Read},
    os::unix::process::{CommandExt, ExitStatusExt},
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use libflatpak::{gio, prelude::CancellableExt};
use smithay::reexports::calloop::{channel, RegistrationToken};

use crate::{
    control_pb::{self as pb, message, request, response},
    flatpak,
    link::Link,
    state::State,
};

/// vsock port the host listens on for the control channel.
pub const CONTROL_PORT: u32 = 5001;
const KILL_GRACE: Duration = Duration::from_secs(5);

/// Messages from worker threads and watchers to the loop thread.
pub enum Note {
    Event(pb::Event),
    Reply(u64, response::Result),
    OpFinished { op: u64, event: pb::Event },
    Exited { launch_id: String, app_id: String, code: i32 },
}

/// A GCancellable handed to a worker thread. GCancellable is documented thread-safe; the
/// loop only ever calls `cancel()` on it, and the worker only reads its state.
struct SendCancel(gio::Cancellable);

// Safety: see the type comment above.
unsafe impl Send for SendCancel {}

impl SendCancel {
    fn get(&self) -> &gio::Cancellable {
        &self.0
    }
}

struct Proc {
    app_id: String,
    pgid: i32,
    exited: Arc<AtomicBool>,
}

pub struct Control {
    pub link: Link,
    pub write_token: Option<RegistrationToken>,
    /// Set by a Shutdown request; the loop stops after the current iteration.
    pub shutdown: bool,
    notes: channel::Sender<Note>,
    /// Environment for launched apps: Wayland socket, runtime dir, session bus, plus Hello values.
    env: Vec<(String, String)>,
    tz: Option<String>,
    locale: Option<String>,
    dark_mode: bool,
    accent_rgb: u32,
    /// Guest-initiated calls waiting for the host's reply (portal backends).
    calls: HashMap<u64, std::sync::mpsc::Sender<pb::CallReply>>,
    next_call: u64,
    ops: HashMap<u64, SendCancel>,
    next_op: u64,
    procs: HashMap<String, Proc>,
    /// Settings/Notification backends; told about every appearance change.
    pub portal: Option<crate::portal::Portal>,
}

impl Control {
    pub fn new(link: Link, notes: channel::Sender<Note>, env: Vec<(String, String)>) -> Self {
        Self {
            link,
            write_token: None,
            shutdown: false,
            notes,
            env,
            tz: None,
            locale: None,
            dark_mode: false,
            accent_rgb: 0,
            calls: HashMap::new(),
            next_call: 1,
            ops: HashMap::new(),
            next_op: 1,
            procs: HashMap::new(),
            portal: None,
        }
    }

    /// Asks the host something only it can answer; the reply arrives on the returned channel.
    pub fn call(&mut self, app_id: &str, body: pb::call::Body) -> std::sync::mpsc::Receiver<pb::CallReply> {
        let id = self.next_call;
        self.next_call += 1;
        let (tx, rx) = std::sync::mpsc::channel();
        self.calls.insert(id, tx);
        let call = pb::Call { id, app_id: app_id.to_owned(), body: Some(body) };
        self.link.send(&pb::Message { body: Some(message::Body::Call(call)) });
        rx
    }

    /// Pushes dark_mode/accent_rgb to the Settings portal; it emits SettingChanged for changes.
    fn publish_appearance(&self) {
        if let Some(portal) = &self.portal {
            portal.set_appearance(crate::portal::settings::Appearance { dark_mode: self.dark_mode, accent_rgb: self.accent_rgb });
        }
    }

    fn reply(&mut self, id: u64, result: response::Result) {
        let msg = pb::Message { body: Some(message::Body::Response(pb::Response { id, result: Some(result) })) };
        self.link.send(&msg);
    }

    fn error(&mut self, id: u64, message: impl Into<String>) {
        self.reply(id, response::Result::Error(pb::Error { message: message.into() }));
    }

    fn event(&mut self, body: pb::event::Body) {
        self.link.send(&pb::Message { body: Some(message::Body::Event(pb::Event { body: Some(body) })) });
    }

    /// Replies from a worker thread: the result is sent back to the loop as a `Note`.
    fn reply_later(&self, id: u64, work: impl FnOnce() -> Result<response::Result, String> + Send + 'static) {
        let notes = self.notes.clone();
        thread::spawn(move || {
            let result = work().unwrap_or_else(|message| response::Result::Error(pb::Error { message }));
            let _ = notes.send(Note::Reply(id, result));
        });
    }

    pub fn handle(&mut self, req: pb::Request) {
        let id = req.id;
        let Some(body) = req.body else {
            return self.error(id, "empty request");
        };
        match body {
            request::Body::Hello(h) => {
                self.tz = (!h.time_zone.is_empty()).then_some(h.time_zone);
                self.locale = (!h.locale.is_empty()).then_some(h.locale);
                self.dark_mode = h.dark_mode;
                self.publish_appearance();
                self.reply(id, response::Result::Ok(pb::Ok {}));
            }
            request::Body::SetAppearance(a) => {
                self.dark_mode = a.dark_mode;
                self.accent_rgb = a.accent_rgb;
                self.publish_appearance();
                self.reply(id, response::Result::Ok(pb::Ok {}));
            }
            request::Body::CallReply(reply) => {
                if let Some(waiting) = self.calls.remove(&reply.id) {
                    let _ = waiting.send(reply);
                }
            }
            request::Body::RefreshCatalog(_) => self.reply_later(id, || {
                flatpak::refresh_catalog()?;
                Ok(response::Result::Ok(pb::Ok {}))
            }),
            request::Body::GetCatalog(_) => self.reply_later(id, || {
                let appstream_xml_gz = flatpak::read_catalog()?;
                Ok(response::Result::Catalog(pb::Catalog { appstream_xml_gz, arch: flatpak::ARCH.into() }))
            }),
            request::Body::ListInstalled(_) => self.reply_later(id, || {
                Ok(response::Result::Installed(pb::InstalledList { apps: flatpak::list_installed()? }))
            }),
            request::Body::Install(r) => self.start_op(id, flatpak::Op::Install(r.app_id)),
            request::Body::Uninstall(r) => {
                self.start_op(id, flatpak::Op::Uninstall { app_id: r.app_id, delete_data: r.delete_data })
            }
            request::Body::Update(r) => self.start_op(id, flatpak::Op::Update(r.app_id)),
            request::Body::Cancel(c) => match self.ops.get(&c.operation) {
                Some(cancel) => {
                    cancel.get().cancel();
                    self.reply(id, response::Result::Ok(pb::Ok {}));
                }
                None => self.error(id, format!("no operation {}", c.operation)),
            },
            request::Body::Launch(l) => match self.launch(&l.app_id, &l.args) {
                Ok(()) => self.reply(id, response::Result::Ok(pb::Ok {})),
                Err(e) => self.error(id, e),
            },
            request::Body::Stop(s) => match self.stop(&s.app_id) {
                Ok(()) => self.reply(id, response::Result::Ok(pb::Ok {})),
                Err(e) => self.error(id, e),
            },
            request::Body::ListRunning(_) => {
                let apps = flatpak::list_running();
                self.reply(id, response::Result::Running(pb::RunningList { apps }));
            }
            request::Body::GetPermissions(p) => {
                let app_id = p.app_id;
                self.reply_later(id, move || Ok(response::Result::Permissions(flatpak::get_permissions(&app_id)?)))
            }
            request::Body::SetPermissions(p) => {
                let (app_id, perms) = (p.app_id, p.permissions.unwrap_or_default());
                self.reply_later(id, move || {
                    flatpak::set_permissions(&app_id, &perms)?;
                    Ok(response::Result::Ok(pb::Ok {}))
                })
            }
            request::Body::Shutdown(_) => {
                self.reply(id, response::Result::Ok(pb::Ok {}));
                self.shutdown = true;
            }
        }
    }

    fn start_op(&mut self, id: u64, op: flatpak::Op) {
        let op_id = self.next_op;
        self.next_op += 1;
        let cancel = SendCancel(gio::Cancellable::new());
        self.ops.insert(op_id, SendCancel(cancel.0.clone()));
        self.reply(id, response::Result::Operation(pb::Operation { id: op_id }));

        let notes = self.notes.clone();
        let app_id = match &op {
            flatpak::Op::Install(a) | flatpak::Op::Update(a) => a.clone(),
            flatpak::Op::Uninstall { app_id, .. } => app_id.clone(),
        };
        thread::spawn(move || {
            let progress_notes = notes.clone();
            let progress_app = app_id.clone();
            let outcome = flatpak::run_op(&op, cancel.get(), move |p| {
                let _ = progress_notes.send(Note::Event(progress_event(op_id, &progress_app, p)));
            });
            let cancelled = matches!(outcome, flatpak::Outcome::Cancelled);
            let error = match outcome {
                flatpak::Outcome::Failed(message) => Some(pb::Error { message }),
                flatpak::Outcome::Done | flatpak::Outcome::Cancelled => None,
            };
            let event = pb::Event {
                body: Some(pb::event::Body::OperationDone(pb::OperationDone {
                    operation: op_id,
                    app_id,
                    error,
                    cancelled,
                })),
            };
            let _ = notes.send(Note::OpFinished { op: op_id, event });
        });
    }

    fn launch(&mut self, app_id: &str, args: &[String]) -> Result<(), String> {
        let launch_id = new_launch_id().map_err(|e| format!("launch id: {e}"))?;
        let mut cmd = Command::new("flatpak");
        cmd.args(["run", "--user", app_id])
            .args(args)
            .envs(self.env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
            .env("CROSSWIND_DARK_MODE", if self.dark_mode { "1" } else { "0" })
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0);
        if let Some(tz) = &self.tz {
            cmd.env("TZ", tz);
        }
        if let Some(locale) = &self.locale {
            cmd.env("LANG", locale);
        }
        let mut child = cmd.spawn().map_err(|e| format!("flatpak run {app_id}: {e}"))?;
        let pid = child.id() as i32;
        if let Some(out) = child.stdout.take() {
            pipe_lines(out, self.notes.clone(), app_id.to_owned(), launch_id.clone(), 6);
        }
        if let Some(err) = child.stderr.take() {
            pipe_lines(err, self.notes.clone(), app_id.to_owned(), launch_id.clone(), 4);
        }

        let exited = Arc::new(AtomicBool::new(false));
        self.procs.insert(launch_id.clone(), Proc { app_id: app_id.to_owned(), pgid: pid, exited });
        let notes = self.notes.clone();
        let (watch_app, watch_id) = (app_id.to_owned(), launch_id.clone());
        thread::spawn(move || {
            let code = match child.wait() {
                Ok(status) => status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0)),
                Err(_) => -1,
            };
            let _ = notes.send(Note::Exited { launch_id: watch_id, app_id: watch_app, code });
        });
        self.event(pb::event::Body::AppStarted(pb::AppStarted {
            app_id: app_id.to_owned(),
            pid: pid as u32,
            launch_id,
        }));
        Ok(())
    }

    /// SIGTERM to every process group of `app_id`, SIGKILL after a grace period if still running.
    fn stop(&mut self, app_id: &str) -> Result<(), String> {
        let targets: Vec<(i32, Arc<AtomicBool>)> = self
            .procs
            .values()
            .filter(|p| p.app_id == app_id)
            .map(|p| (p.pgid, p.exited.clone()))
            .collect();
        if targets.is_empty() {
            return Err(format!("{app_id} is not running"));
        }
        for (pgid, exited) in targets {
            signal_group(pgid, libc::SIGTERM);
            thread::spawn(move || {
                thread::sleep(KILL_GRACE);
                if !exited.load(Ordering::SeqCst) {
                    signal_group(pgid, libc::SIGKILL);
                }
            });
        }
        Ok(())
    }

    /// The app and launch that own `pid`, found by walking its ancestors up to a `flatpak run` we started.
    pub fn owner_of(&self, mut pid: i32) -> Option<(&str, &str)> {
        for _ in 0..64 {
            if let Some((launch_id, proc)) = self.procs.iter().find(|(_, p)| p.pgid == pid) {
                return Some((&proc.app_id, launch_id));
            }
            pid = parent_pid(pid)?;
            if pid <= 1 {
                return None;
            }
        }
        None
    }

    /// Handles a note sent from a worker or watcher thread.
    pub fn on_note(&mut self, note: Note) {
        match note {
            Note::Event(ev) => self.link.send(&pb::Message { body: Some(message::Body::Event(ev)) }),
            Note::Reply(id, result) => self.reply(id, result),
            Note::OpFinished { op, event } => {
                self.ops.remove(&op);
                self.link.send(&pb::Message { body: Some(message::Body::Event(event)) });
            }
            Note::Exited { launch_id, app_id, code } => {
                if let Some(proc) = self.procs.remove(&launch_id) {
                    proc.exited.store(true, Ordering::SeqCst);
                }
                self.event(pb::event::Body::AppExited(pb::AppExited { app_id, exit_code: code, launch_id }));
            }
        }
    }
}

fn progress_event(op: u64, app_id: &str, p: flatpak::Progress) -> pb::Event {
    pb::Event {
        body: Some(pb::event::Body::Progress(pb::Progress {
            operation: op,
            app_id: app_id.to_owned(),
            phase: p.phase.to_owned(),
            detail: p.detail,
            percent: p.percent,
            bytes_transferred: p.bytes_transferred,
            bytes_total: p.bytes_total,
        })),
    }
}

fn pipe_lines(reader: impl Read + Send + 'static, notes: channel::Sender<Note>, app_id: String, launch_id: String, level: i32) {
    thread::spawn(move || {
        for line in BufReader::new(reader).lines().map_while(Result::ok) {
            let log = pb::LogLine {
                source: app_id.clone(),
                launch_id: launch_id.clone(),
                level,
                text: line,
                unix_time_ms: now_ms(),
            };
            let ev = pb::Event { body: Some(pb::event::Body::Log(log)) };
            if notes.send(Note::Event(ev)).is_err() {
                break;
            }
        }
    });
}

fn parent_pid(pid: i32) -> Option<i32> {
    parse_ppid(&std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?)
}

/// `/proc/<pid>/stat` is `pid (comm) state ppid ...`; comm may itself contain spaces and parentheses.
fn parse_ppid(stat: &str) -> Option<i32> {
    stat[stat.rfind(')')? + 1..].split_whitespace().nth(1)?.parse().ok()
}

fn signal_group(pgid: i32, sig: i32) {
    // Safety: kill(2) on a negative pid signals a process group; errors (already gone) are ignored.
    unsafe {
        libc::kill(-pgid, sig);
    }
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// 16 random bytes as hex, from the kernel RNG.
fn new_launch_id() -> io::Result<String> {
    let mut buf = [0u8; 16];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut buf)?;
    Ok(buf.iter().map(|b| format!("{b:02x}")).collect())
}

/// Returns the session bus address, starting a session `dbus-daemon` when none is inherited.
pub fn session_bus() -> io::Result<String> {
    if let Ok(addr) = std::env::var("DBUS_SESSION_BUS_ADDRESS")
        && !addr.is_empty()
    {
        return Ok(addr);
    }
    let out = Command::new("dbus-daemon").args(["--session", "--fork", "--print-address"]).output()?;
    if !out.status.success() {
        return Err(io::Error::other("dbus-daemon --session failed"));
    }
    let addr = String::from_utf8_lossy(&out.stdout).trim().to_owned();
    if addr.is_empty() {
        return Err(io::Error::other("dbus-daemon printed no address"));
    }
    Ok(addr)
}

impl State {
    pub fn on_control_readable(&mut self) {
        match self.control.link.recv::<pb::Request>() {
            Ok(requests) => {
                for req in requests {
                    self.control.handle(req);
                }
                if self.control.shutdown {
                    self.loop_signal.stop();
                }
            }
            Err(e) => {
                tracing::error!("control link lost: {e}");
                self.loop_signal.stop();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ppid_parses_commands_with_spaces_and_parens() {
        assert_eq!(parse_ppid("42 (bwrap (x) y) S 7 42 42 0"), Some(7));
        assert_eq!(parse_ppid("garbage"), None);
    }

    #[test]
    fn launch_ids_are_32_hex_chars_and_distinct() {
        let a = new_launch_id().unwrap();
        let b = new_launch_id().unwrap();
        assert_eq!(a.len(), 32);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
        assert_ne!(a, b);
    }

    #[test]
    fn progress_event_maps_fields() {
        let ev = progress_event(
            7,
            "org.example.App",
            flatpak::Progress { phase: "install", detail: "app/x".into(), percent: 42, bytes_transferred: 10, bytes_total: 20 },
        );
        match ev.body {
            Some(pb::event::Body::Progress(p)) => {
                assert_eq!((p.operation, p.percent, p.bytes_total), (7, 42, 20));
                assert_eq!(p.phase, "install");
                assert_eq!(p.app_id, "org.example.App");
            }
            other => panic!("unexpected {other:?}"),
        }
    }
}
