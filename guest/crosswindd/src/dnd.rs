// SPDX-License-Identifier: AGPL-3.0-or-later
//! Drag and drop between the Mac and guest apps.
//!
//! Mac to Linux: the host announces a drag (`DragEnter`, types only), follows it (`DragMotion`) and delivers the data
//! with `DragDrop`. Here that is a pointer grab driven by a `HostSource`, so apps see an ordinary `wl_data_offer`.
//! Linux to Mac: when an app starts a drag, its text and file list are read at once and sent as `DragStarted`; the
//! host starts a native drag when the pointer leaves the app's windows.

use std::{
    io::Write,
    os::fd::OwnedFd,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use smithay::{
    input::{
        dnd::{DnDGrab, DndAction, Source, SourceMetadata},
        pointer::{Focus, GrabStartData},
    },
    utils::{IsAlive, SERIAL_COUNTER},
};

use crate::{
    clipboard::read_capped,
    control::Note,
    limits,
    pb::{self, input::Event},
    state::State,
};

const BTN_LEFT: u32 = 0x110;
const TEXT_MIMES: [&str; 2] = ["text/plain;charset=utf-8", "text/plain"];
const URI_LIST: &str = "text/uri-list";
const READ_TIMEOUT: Duration = Duration::from_secs(2);

/// What the Mac dropped, shared with the thread that answers `send`.
#[derive(Default)]
struct Payload {
    text: String,
    uris: Vec<String>,
}

/// The data source of a drag that comes from the Mac.
pub struct HostSource {
    window: u32,
    mimes: Vec<String>,
    payload: Arc<Mutex<Payload>>,
    alive: Arc<AtomicBool>,
    notes: smithay::reexports::calloop::channel::Sender<Note>,
}

impl IsAlive for HostSource {
    fn alive(&self) -> bool {
        self.alive.load(Ordering::Relaxed)
    }
}

impl Source for HostSource {
    fn metadata(&self) -> Option<SourceMetadata> {
        Some(SourceMetadata { mime_types: self.mimes.clone(), dnd_actions: [DndAction::Copy].into_iter().collect() })
    }

    fn accepted(&self, mime_type: Option<String>) {
        let status = pb::DragStatus { window: self.window, accepted: mime_type.is_some() };
        let _ = self.notes.send(Note::Display(pb::to_host::Msg::DragStatus(status)));
    }

    fn choose_action(&self, _: DndAction) {}

    fn send(&self, mime_type: &str, fd: OwnedFd) {
        let Some(body) = self.body(mime_type) else { return };
        // The app reads at its own pace; a worker thread keeps the loop from waiting on it.
        thread::spawn(move || {
            let _ = std::fs::File::from(fd).write_all(&body);
        });
    }

    fn drop_performed(&self) {}

    fn cancel(&self) {
        self.alive.store(false, Ordering::Relaxed);
    }

    fn finished(&self) {
        self.alive.store(false, Ordering::Relaxed);
    }
}

impl HostSource {
    fn body(&self, mime: &str) -> Option<Vec<u8>> {
        let payload = self.payload.lock().ok()?;
        if mime == URI_LIST {
            Some(uri_list(&payload.uris).into_bytes())
        } else if TEXT_MIMES.contains(&mime) {
            Some(payload.text.clone().into_bytes())
        } else {
            None
        }
    }
}

/// `text/uri-list` body: one URI per line, CRLF terminated.
pub fn uri_list(uris: &[String]) -> String {
    uris.iter().map(|u| format!("{u}\r\n")).collect()
}

/// The `file://` URI of a guest path that the host may hand to an app: absolute, inside the Mac share, no `..`,
/// no control characters. `None` for anything else.
pub fn file_uri(path: &str) -> Option<String> {
    let ok = path.len() <= limits::MAX_PATH
        && path.starts_with(limits::MAC_SHARE_PREFIX)
        && !path.chars().any(char::is_control)
        && path.split('/').all(|part| part != "..");
    if !ok {
        return None;
    }
    let mut uri = String::from("file://");
    for byte in path.bytes() {
        if byte.is_ascii_alphanumeric() || b"/._~-".contains(&byte) {
            uri.push(byte as char);
        } else {
            uri.push_str(&format!("%{byte:02X}"));
        }
    }
    Some(uri)
}

/// Guest path of a `file://` URI an app offered; `None` for other schemes, hosts and malformed escapes.
pub fn uri_path(uri: &str) -> Option<String> {
    let rest = uri.strip_prefix("file://")?;
    let rest = rest.strip_prefix("localhost").unwrap_or(rest);
    if !rest.starts_with('/') {
        return None;
    }
    let bytes = rest.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = rest.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok().filter(|p| p.len() <= limits::MAX_PATH && !p.chars().any(char::is_control))
}

fn now_ms() -> u32 {
    static START: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
    START.get_or_init(Instant::now).elapsed().as_millis() as u32
}

impl State {
    /// A drag from the Mac entered `window`: start a drag grab whose source offers what the Mac holds.
    pub fn drag_enter(&mut self, e: pb::DragEnter) {
        if !limits::finite(e.x) || !limits::finite(e.y) || self.win_by_id(e.window).is_none() {
            return;
        }
        self.drag_cancel(e.window);
        let mut mimes = Vec::new();
        if e.offers_text {
            mimes.extend(TEXT_MIMES.map(String::from));
        }
        if e.offers_files {
            mimes.push(URI_LIST.to_owned());
        }
        if mimes.is_empty() {
            return;
        }
        let payload = Arc::new(Mutex::new(Payload::default()));
        let alive = Arc::new(AtomicBool::new(true));
        let source = HostSource {
            window: e.window,
            mimes,
            payload: payload.clone(),
            alive: alive.clone(),
            notes: self.control.notes_sender(),
        };
        let Some(ptr) = self.seat.get_pointer() else { return };
        let start = GrabStartData { focus: None, button: BTN_LEFT, location: (0.0, 0.0).into() };
        let grab = DnDGrab::new_pointer(&self.display_handle, start, source, self.seat.clone());
        ptr.set_grab(self, grab, SERIAL_COUNTER.next_serial(), Focus::Keep);
        self.host_drag = Some(HostDrag { window: e.window, payload });
        self.drag_motion(pb::DragMotion { window: e.window, x: e.x, y: e.y });
    }

    pub fn drag_motion(&mut self, m: pb::DragMotion) {
        if self.host_drag.as_ref().is_none_or(|d| d.window != m.window) {
            return;
        }
        let event = Event::Motion(pb::PointerMotion { x: m.x, y: m.y, time_ms: now_ms() });
        self.input(pb::Input { window: m.window, event: Some(event) });
    }

    /// The Mac dropped: hand the data to the source, then release the (virtual) button so the grab performs the drop.
    pub fn drag_drop(&mut self, d: pb::DragDrop) {
        let Some(drag) = self.host_drag.take_if(|drag| drag.window == d.window) else { return };
        if d.text.len() > limits::MAX_DRAG_TEXT || d.paths.len() > limits::MAX_FILES {
            return self.end_grab();
        }
        if let Ok(mut payload) = drag.payload.lock() {
            payload.text = d.text;
            payload.uris = d.paths.iter().filter_map(|p| file_uri(p)).collect();
        }
        let event = Event::Button(pb::PointerButton { button: BTN_LEFT, pressed: false, time_ms: now_ms() });
        self.input(pb::Input { window: d.window, event: Some(event) });
    }

    /// The Mac drag left the window, or the host took over a drag that began here.
    pub fn drag_cancel(&mut self, window: u32) {
        if self.host_drag.as_ref().is_some_and(|d| d.window == window) {
            self.host_drag = None;
            self.end_grab();
        } else if self.guest_drag == Some(window) {
            self.guest_drag = None;
            self.end_grab();
        }
    }

    fn end_grab(&mut self) {
        if let Some(ptr) = self.seat.get_pointer()
            && ptr.is_grabbed()
        {
            ptr.unset_grab(self, SERIAL_COUNTER.next_serial(), smithay::backend::input::InputTime::from_millis(now_ms()));
        }
    }

    /// An app started a drag: read what it offers and tell the host (see `DragStarted`).
    pub fn guest_drag_started<S: Source>(&mut self, source: &S) {
        let Some(window) = self.pointer_window else {
            tracing::debug!("guest drag without a pointer window");
            return;
        };
        self.guest_drag = Some(window);
        let offered = source.metadata().map(|m| m.mime_types).unwrap_or_default();
        tracing::debug!(window, ?offered, "guest drag started");
        let deadline = Instant::now() + READ_TIMEOUT;
        let read = |wanted: &[&str], cap: usize| -> Option<std::thread::JoinHandle<Option<Vec<u8>>>> {
            let mime = wanted.iter().find(|m| offered.iter().any(|o| o == **m))?;
            let (reader, writer) = std::io::pipe().ok()?;
            source.send(mime, writer.into());
            Some(thread::spawn(move || read_capped(reader.into(), cap, deadline)))
        };
        let text = read(&TEXT_MIMES, limits::MAX_DRAG_TEXT);
        let uris = read(&[URI_LIST], 64 * 1024);
        if text.is_none() && uris.is_none() {
            return;
        }
        let notes = self.control.notes_sender();
        thread::spawn(move || {
            let text = text.and_then(|t| t.join().ok().flatten()).and_then(|t| String::from_utf8(t).ok());
            let uris = uris.and_then(|t| t.join().ok().flatten()).and_then(|t| String::from_utf8(t).ok());
            let uris: Vec<String> = uris
                .iter()
                .flat_map(|list| list.lines())
                .filter(|line| !line.starts_with('#'))
                .filter_map(|line| uri_path(line.trim()).and_then(|p| file_uri(&p)))
                .take(limits::MAX_FILES)
                .collect();
            let text = text.unwrap_or_default();
            if text.is_empty() && uris.is_empty() {
                return;
            }
            tracing::debug!(window, text_bytes = text.len(), files = uris.len(), "guest drag sent to the host");
            let started = pb::DragStarted { window, text, uris };
            let _ = notes.send(Note::Display(pb::to_host::Msg::DragStarted(started)));
        });
    }
}

/// A drag from the Mac that is in progress.
pub struct HostDrag {
    window: u32,
    payload: Arc<Mutex<Payload>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uris_are_escaped_and_confined_to_the_mac_share() {
        assert_eq!(file_uri("/mnt/mac/docs/a b.txt").as_deref(), Some("file:///mnt/mac/docs/a%20b.txt"));
        assert_eq!(file_uri("/etc/passwd"), None);
        assert_eq!(file_uri("/mnt/mac/../etc/passwd"), None);
        assert_eq!(file_uri("/mnt/mac/a\nb"), None);
    }

    #[test]
    fn uri_paths_decode_and_refuse_other_hosts() {
        assert_eq!(uri_path("file:///mnt/mac/a%20b").as_deref(), Some("/mnt/mac/a b"));
        assert_eq!(uri_path("file://localhost/mnt/mac/x").as_deref(), Some("/mnt/mac/x"));
        assert_eq!(uri_path("file://evil/mnt/mac/x"), None);
        assert_eq!(uri_path("http://example.com/"), None);
        assert_eq!(uri_path("file:///mnt/mac/%zz"), None);
        assert_eq!(uri_path("file:///mnt/mac/%00"), None);
    }

    /// Seeded random bytes through both URI functions: no panics, every URI is plain ASCII under the Mac share, and a
    /// valid path survives the round trip.
    #[test]
    fn hostile_paths_and_uris_never_escape_the_share() {
        let mut state = 0x9E37_79B9_7F4A_7C15u64;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let alphabet: Vec<char> = "abc/._-%20\n\0..~é ".chars().collect();
        for _ in 0..20_000 {
            let len = (next() % 40) as usize;
            let text: String = (0..len).map(|_| alphabet[(next() % alphabet.len() as u64) as usize]).collect();
            let candidate = format!("/mnt/mac/{text}");
            if let Some(uri) = file_uri(&candidate) {
                assert!(uri.is_ascii() && uri.starts_with("file:///mnt/mac/"), "{uri}");
                assert!(uri.split('/').all(|part| part != ".."), "{uri}");
                assert_eq!(uri_path(&uri).as_deref(), Some(candidate.as_str()));
            }
            if let Some(path) = uri_path(&format!("file://{text}")) {
                assert!(!path.chars().any(char::is_control));
            }
        }
    }

    #[test]
    fn uri_lists_end_every_line_with_crlf() {
        assert_eq!(uri_list(&["a".into(), "b".into()]), "a\r\nb\r\n");
    }
}
