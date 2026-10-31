// SPDX-License-Identifier: AGPL-3.0-or-later
//! URL handler socket: `crosswind-open` (the guest's `xdg-open`) sends one URL per connection and
//! reads back one status line. The URL goes to the host as `Call::OpenUrl`.
//!
//! Wire format: client writes `<url>\n`; server answers `ok\n` or `err <message>\n`.

use std::{
    io::{self, BufRead, BufReader, Read, Write},
    os::unix::net::{UnixListener, UnixStream},
    thread,
    time::Duration,
};

use smithay::reexports::calloop::{Interest, LoopHandle, Mode, PostAction, generic::Generic};

use super::Bridge;
use crate::control_pb::{self as pb, call, call_reply};

pub const SOCKET_PATH: &str = "/run/crosswind/open-url.sock";
const MAX_URL: usize = 8192;
const CLIENT_TIMEOUT: Duration = Duration::from_secs(5);

/// Binds the socket and accepts connections from the loop. Each connection gets its own thread,
/// so a slow client never stalls the loop.
pub fn listen<D: 'static>(handle: &LoopHandle<'static, D>, bridge: Bridge) -> io::Result<()> {
    let _ = std::fs::remove_file(SOCKET_PATH);
    let listener = UnixListener::bind(SOCKET_PATH)?;
    listener.set_nonblocking(true)?;
    handle
        .insert_source(Generic::new(listener, Interest::READ, Mode::Level), move |_, listener, _| {
            loop {
                // Safety: the listener is only accepted from, never dropped or replaced here.
                let accepted = unsafe { listener.get_mut() }.accept();
                match accepted {
                    Ok((stream, _)) => {
                        let bridge = bridge.clone();
                        thread::spawn(move || serve(stream, &bridge));
                    }
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                    Err(e) => {
                        tracing::warn!("open-url accept: {e}");
                        break;
                    }
                }
            }
            Ok(PostAction::Continue)
        })
        .map_err(|e| io::Error::other(e.to_string()))?;
    Ok(())
}

fn serve(stream: UnixStream, bridge: &Bridge) {
    let _ = stream.set_nonblocking(false);
    let _ = stream.set_read_timeout(Some(CLIENT_TIMEOUT));
    let status = match read_url(&stream).and_then(|url| open_on_host(bridge, url)) {
        Ok(()) => "ok".to_owned(),
        Err(e) => format!("err {e}"),
    };
    let mut out = &stream;
    let _ = writeln!(out, "{status}");
}

fn read_url(stream: &UnixStream) -> Result<String, String> {
    let mut line = String::new();
    BufReader::new(stream.take(MAX_URL as u64 + 2)).read_line(&mut line).map_err(|e| format!("read: {e}"))?;
    parse_request(&line)
}

fn open_on_host(bridge: &Bridge, url: String) -> Result<(), String> {
    let reply = bridge.call_blocking("", call::Body::OpenUrl(pb::OpenUrl { url }))?;
    match reply.result {
        Some(call_reply::Result::Ok(_)) => Ok(()),
        Some(call_reply::Result::Error(e)) => Err(e.message),
        _ => Err("unexpected host reply".to_owned()),
    }
}

/// Validates one request line and returns the URL it carries.
pub fn parse_request(line: &str) -> Result<String, String> {
    let url = line.trim_end_matches(['\r', '\n']);
    if url.is_empty() {
        return Err("empty url".to_owned());
    }
    if url.len() > MAX_URL {
        return Err("url too long".to_owned());
    }
    if url.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return Err("url contains whitespace or control characters".to_owned());
    }
    if !url.contains(':') {
        return Err("not a URL".to_owned());
    }
    Ok(url.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_urls_and_strips_newline() {
        assert_eq!(parse_request("https://example.com/a?b=c\n").unwrap(), "https://example.com/a?b=c");
        assert_eq!(parse_request("mailto:me@example.com").unwrap(), "mailto:me@example.com");
    }

    #[test]
    fn rejects_bad_requests() {
        assert!(parse_request("\n").is_err());
        assert!(parse_request("example.com").is_err());
        assert!(parse_request("https://a b\n").is_err());
        assert!(parse_request(&format!("https://{}", "a".repeat(MAX_URL))).is_err());
    }
}
