// SPDX-License-Identifier: AGPL-3.0-or-later
//! Framed protobuf connection to the host over vsock.
//!
//! Wire format: little-endian u32 length, then one serialized message. The socket is
//! non-blocking; unwritten bytes stay queued until the loop reports it writable.

use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::{AsFd, BorrowedFd};
use std::time::Duration;

use prost::Message;
use smithay::reexports::calloop::{Interest, LoopHandle, Mode, PostAction, RegistrationToken, generic::Generic};
use vsock::{VMADDR_CID_HOST, VsockAddr, VsockStream};

const MAX_FRAME: usize = 64 << 20;

pub struct Link {
    stream: VsockStream,
    inbox: Vec<u8>,
    outbox: Vec<u8>,
}

impl Link {
    /// Connects to the host listener on `port`, retrying until it appears.
    pub fn connect(port: u32) -> io::Result<Self> {
        loop {
            match VsockStream::connect(&VsockAddr::new(VMADDR_CID_HOST, port)) {
                Ok(stream) => {
                    stream.set_nonblocking(true)?;
                    return Ok(Self { stream, inbox: Vec::new(), outbox: Vec::new() });
                }
                Err(e) => {
                    tracing::debug!("host not ready on port {port}: {e}");
                    std::thread::sleep(Duration::from_millis(250));
                }
            }
        }
    }

    pub fn fd(&self) -> BorrowedFd<'_> {
        self.stream.as_fd()
    }

    pub fn wants_write(&self) -> bool {
        !self.outbox.is_empty()
    }

    pub fn send<M: Message>(&mut self, msg: &M) {
        self.outbox.extend_from_slice(&(msg.encoded_len() as u32).to_le_bytes());
        msg.encode(&mut self.outbox).expect("Vec grows");
    }

    /// Writes as much queued output as the socket accepts. `Err` means the link is gone.
    pub fn flush(&mut self) -> io::Result<()> {
        while !self.outbox.is_empty() {
            match self.stream.write(&self.outbox) {
                Ok(n) => {
                    self.outbox.drain(..n);
                }
                Err(e) if e.kind() == ErrorKind::WouldBlock => return Ok(()),
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    /// Reads whatever is available and returns every complete message. `Err` means EOF or failure.
    pub fn recv<M: Message + Default>(&mut self) -> io::Result<Vec<M>> {
        let mut buf = [0u8; 64 * 1024];
        loop {
            match self.stream.read(&mut buf) {
                Ok(0) => return Err(ErrorKind::UnexpectedEof.into()),
                Ok(n) => self.inbox.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(e) => return Err(e),
            }
        }
        let mut out = Vec::new();
        while let Some(head) = self.inbox.get(..4) {
            let mut len_bytes = [0u8; 4];
            len_bytes.copy_from_slice(head);
            let len = u32::from_le_bytes(len_bytes) as usize;
            if len > MAX_FRAME {
                return Err(io::Error::new(ErrorKind::InvalidData, "oversized frame"));
            }
            if self.inbox.len() < 4 + len {
                break;
            }
            // The length prefix is intact, so a body that does not decode is skipped, not fatal.
            match M::decode(&self.inbox[4..4 + len]) {
                Ok(msg) => out.push(msg),
                Err(e) => tracing::warn!("dropped undecodable message ({len} bytes): {e}"),
            }
            self.inbox.drain(..4 + len);
        }
        Ok(out)
    }
}

/// Keeps a write-readiness source registered while `link` has queued bytes.
///
/// Call after `link.flush()`. `select` reaches the link and its token inside the loop state `D`;
/// `on_error` runs when a later flush from the loop fails.
pub fn arm_write<D: 'static>(
    handle: &LoopHandle<'static, D>,
    link: &Link,
    token: &mut Option<RegistrationToken>,
    select: fn(&mut D) -> (&mut Link, &mut Option<RegistrationToken>),
    on_error: fn(&mut D),
) {
    if !link.wants_write() || token.is_some() {
        return;
    }
    let Ok(fd) = link.fd().try_clone_to_owned() else {
        tracing::error!("cannot duplicate the vsock descriptor; write readiness not armed");
        return;
    };
    let registered = handle.insert_source(Generic::new(fd, Interest::WRITE, Mode::Level), move |_, _, state| {
        if select(state).0.flush().is_err() {
            on_error(state);
            return Ok(PostAction::Remove);
        }
        let (link, token) = select(state);
        if link.wants_write() {
            Ok(PostAction::Continue)
        } else {
            *token = None;
            Ok(PostAction::Remove)
        }
    });
    *token = Some(registered.expect("write source"));
}
