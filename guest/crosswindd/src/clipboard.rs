// SPDX-License-Identifier: AGPL-3.0-or-later
//! Clipboard bridge between the Mac host and guest apps.
//!
//! Mac to guest: the host announces its clipboard types (`OfferClipboard`). The guest owns the Wayland
//! selection through a compositor source; when an app pastes, the bytes are fetched from the host with a
//! `Call::ClipboardRead`.
//!
//! Guest to Mac: a guest copy is read eagerly (size-capped, time-limited) and sent as `ClipboardChanged`.

use std::{
    fs::File,
    io::{self, Read, Write},
    os::fd::{AsRawFd, OwnedFd},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

use smithay::{
    input::Seat,
    reexports::calloop::channel,
    wayland::selection::{
        SelectionSource,
        data_device::{clear_data_device_selection, request_data_device_client_selection, set_data_device_selection},
    },
};

use crate::{
    control::Note,
    control_pb as pb,
    state::State,
};

pub const TEXT_MIME: &str = "text/plain;charset=utf-8";
const IMAGE_MIME: &str = "image/png";
const HTML_MIME: &str = "text/html";
/// Source mimes that carry text, in order of preference.
const TEXT_SOURCES: [&str; 3] = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING"];
const TEXT_CAP: usize = 1 << 20;
const OTHER_CAP: usize = 16 << 20;
const PASTE_TIMEOUT: Duration = Duration::from_secs(5);
const COPY_TIMEOUT: Duration = Duration::from_secs(2);
/// Slack past the copy deadline before the collector gives up on a reader thread.
const COLLECT_GRACE: Duration = Duration::from_millis(100);

/// `SelectionUserData` of the compositor-owned selection: marks it as ours.
#[derive(Clone, Copy, Debug)]
pub struct Offered;

/// A guest copy type to read: the mime requested from the source, the canonical mime sent to the host,
/// and the size cap in bytes.
#[derive(Debug, PartialEq, Eq)]
pub struct CopyItem {
    pub request: String,
    pub mime: &'static str,
    pub cap: usize,
}

/// The host mime for a mime a guest app asks for, or `None` when the bridge does not carry it.
pub fn host_mime(guest: &str) -> Option<&'static str> {
    match guest {
        "text/plain;charset=utf-8" | "text/plain" | "UTF8_STRING" | "STRING" | "TEXT" => Some(TEXT_MIME),
        IMAGE_MIME => Some(IMAGE_MIME),
        HTML_MIME => Some(HTML_MIME),
        _ => None,
    }
}

/// Largest payload accepted for a host mime; larger items are dropped.
pub fn size_cap(mime: &str) -> usize {
    if mime == TEXT_MIME { TEXT_CAP } else { OTHER_CAP }
}

/// The items to read from a guest copy: one text type (the most preferred one offered), then image and HTML.
pub fn pick_items(offered: &[String]) -> Vec<CopyItem> {
    let has = |mime: &str| offered.iter().any(|o| o == mime);
    let mut items = Vec::new();
    if let Some(request) = TEXT_SOURCES.iter().copied().find(|m| has(m)) {
        items.push(CopyItem { request: request.to_owned(), mime: TEXT_MIME, cap: size_cap(TEXT_MIME) });
    }
    for mime in [IMAGE_MIME, HTML_MIME] {
        if has(mime) {
            items.push(CopyItem { request: mime.to_owned(), mime, cap: size_cap(mime) });
        }
    }
    items
}

/// Makes the host's clipboard the guest selection. An empty list clears it.
pub fn offer(state: &mut State, mimes: Vec<String>) {
    let dh = state.display_handle.clone();
    let seat = state.seat.clone();
    if mimes.is_empty() {
        clear_data_device_selection(&dh, &seat);
    } else {
        set_data_device_selection(&dh, &seat, mimes, Offered);
    }
}

/// The Flatpak app that owns the keyboard focus, or empty when there is none.
fn focused_app(state: &State, seat: &Seat<State>) -> String {
    seat.get_keyboard()
        .and_then(|kb| kb.current_focus())
        .and_then(|surface| state.owner_of(&surface))
        .map(|(app, _)| app)
        .unwrap_or_default()
}

/// A guest app pastes `mime`: fetch it from the host and write it into `fd` from a worker thread.
/// On a host error or timeout the fd is closed without data.
pub fn paste(state: &mut State, seat: &Seat<State>, mime: String, fd: OwnedFd) {
    let Some(host) = host_mime(&mime) else { return };
    let app_id = focused_app(state, seat);
    let body = pb::call::Body::ClipboardRead(pb::ClipboardRead { mime: host.to_owned() });
    let reply = state.control.call(&app_id, body);
    thread::spawn(move || {
        let data = reply
            .recv_timeout(PASTE_TIMEOUT)
            .ok()
            .and_then(|reply| match reply.result {
                Some(pb::call_reply::Result::Clipboard(data)) => Some(data.data),
                _ => None,
            });
        // The host's data is untrusted in size too: anything over the cap for its type is dropped.
        if let Some(data) = data.filter(|d| d.len() <= size_cap(host)) {
            let _ = File::from(fd).write_all(&data);
        }
    });
}

/// A guest app copied: read the offered types on worker threads and send them to the host as one event.
/// Nothing is sent when no type could be read, so the host keeps its clipboard.
pub fn copy(seat: &Seat<State>, source: &SelectionSource, notes: channel::Sender<Note>) {
    let items = pick_items(&source.mime_types());
    if items.is_empty() {
        return;
    }
    let deadline = Instant::now() + COPY_TIMEOUT;
    let (tx, rx) = mpsc::channel::<(usize, Option<pb::ClipboardData>)>();
    let mut pending = 0usize;
    for (index, item) in items.into_iter().enumerate() {
        let Ok((reader, writer)) = io::pipe() else { continue };
        if request_data_device_client_selection(seat, item.request.clone(), writer.into()).is_err() {
            continue;
        }
        pending += 1;
        let tx = tx.clone();
        thread::spawn(move || {
            let data = read_capped(reader.into(), item.cap, deadline)
                .map(|data| pb::ClipboardData { mime: item.mime.to_owned(), data });
            let _ = tx.send((index, data));
        });
    }
    drop(tx);
    if pending == 0 {
        return;
    }
    thread::spawn(move || {
        let mut got = Vec::with_capacity(pending);
        for _ in 0..pending {
            let wait = deadline.saturating_duration_since(Instant::now()) + COLLECT_GRACE;
            match rx.recv_timeout(wait) {
                Ok((index, Some(data))) => got.push((index, data)),
                Ok((_, None)) => {}
                Err(_) => break,
            }
        }
        if got.is_empty() {
            return;
        }
        got.sort_by_key(|(index, _)| *index);
        let items = got.into_iter().map(|(_, data)| data).collect();
        let body = pb::event::Body::ClipboardChanged(pb::ClipboardChanged { items });
        let _ = notes.send(Note::Event(pb::Event { body: Some(body) }));
    });
}

/// Reads `fd` until EOF. `None` when the data exceeds `cap`, the deadline passes, or the read fails.
pub fn read_capped(fd: OwnedFd, cap: usize, deadline: Instant) -> Option<Vec<u8>> {
    let mut file = File::from(fd);
    if !set_nonblocking(file.as_raw_fd()) {
        return None;
    }
    let mut out = Vec::new();
    let mut chunk = vec![0u8; 64 * 1024];
    loop {
        let left = deadline.checked_duration_since(Instant::now())?;
        if !poll_readable(file.as_raw_fd(), left) {
            return None;
        }
        match file.read(&mut chunk) {
            Ok(0) => return Some(out),
            Ok(n) => {
                out.extend_from_slice(&chunk[..n]);
                if out.len() > cap {
                    return None;
                }
            }
            Err(e) if matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted) => {}
            Err(_) => return None,
        }
    }
}

fn set_nonblocking(fd: i32) -> bool {
    // SAFETY: fcntl on a descriptor we own; no pointers are passed.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        flags >= 0 && libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) == 0
    }
}

/// Waits up to `timeout` for `fd` to become readable or hang up.
fn poll_readable(fd: i32, timeout: Duration) -> bool {
    let ms = timeout.as_millis().min(i32::MAX as u128) as i32;
    let mut pfd = libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
    loop {
        // SAFETY: one valid pollfd, passed by pointer for the duration of the call.
        let r = unsafe { libc::poll(&mut pfd, 1, ms) };
        if r > 0 {
            return true;
        }
        if r == 0 || io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
            return false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strs(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn text_aliases_map_to_host_text() {
        for alias in ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"] {
            assert_eq!(host_mime(alias), Some(TEXT_MIME), "{alias}");
        }
        assert_eq!(host_mime("image/png"), Some("image/png"));
        assert_eq!(host_mime("text/html"), Some("text/html"));
        assert_eq!(host_mime("application/octet-stream"), None);
        assert_eq!(host_mime(""), None);
    }

    #[test]
    fn size_caps_by_type() {
        assert_eq!(size_cap(TEXT_MIME), 1 << 20);
        assert_eq!(size_cap("image/png"), 16 << 20);
        assert_eq!(size_cap("text/html"), 16 << 20);
    }

    #[test]
    fn picks_preferred_text_and_other_types() {
        let items = pick_items(&strs(&["UTF8_STRING", "text/plain;charset=utf-8", "image/png"]));
        assert_eq!(
            items,
            vec![
                CopyItem { request: "text/plain;charset=utf-8".into(), mime: TEXT_MIME, cap: 1 << 20 },
                CopyItem { request: "image/png".into(), mime: "image/png", cap: 16 << 20 },
            ]
        );
        let items = pick_items(&strs(&["UTF8_STRING", "text/html"]));
        assert_eq!(items[0].request, "UTF8_STRING");
        assert_eq!(items[0].mime, TEXT_MIME);
        assert_eq!(items[1].mime, "text/html");
    }

    #[test]
    fn picks_nothing_for_unknown_types() {
        assert!(pick_items(&strs(&["application/x-foo", "text/uri-list"])).is_empty());
        assert!(pick_items(&[]).is_empty());
    }

    #[test]
    fn read_capped_returns_data_under_cap() {
        let (reader, mut writer) = io::pipe().unwrap();
        writer.write_all(b"hello").unwrap();
        drop(writer);
        let deadline = Instant::now() + Duration::from_secs(1);
        assert_eq!(read_capped(reader.into(), 16, deadline), Some(b"hello".to_vec()));
    }

    #[test]
    fn read_capped_drops_data_over_cap() {
        let (reader, mut writer) = io::pipe().unwrap();
        writer.write_all(&[7u8; 100]).unwrap();
        drop(writer);
        let deadline = Instant::now() + Duration::from_secs(1);
        assert_eq!(read_capped(reader.into(), 10, deadline), None);
    }

    #[test]
    fn read_capped_times_out_on_open_pipe() {
        let (reader, _writer) = io::pipe().unwrap();
        let deadline = Instant::now() + Duration::from_millis(50);
        assert_eq!(read_capped(reader.into(), 1024, deadline), None);
    }
}
