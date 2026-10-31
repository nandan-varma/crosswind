// SPDX-License-Identifier: AGPL-3.0-or-later
//! Framed protobuf connection to the host over vsock.
//!
//! Wire format: little-endian u32 length, then one serialized message. The socket is
//! non-blocking; unwritten bytes stay queued until the loop reports it writable.

use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::{AsFd, BorrowedFd};
use std::time::Duration;

use prost::Message;
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
            let len = u32::from_le_bytes(head.try_into().expect("4 bytes")) as usize;
            if len > MAX_FRAME {
                return Err(io::Error::new(ErrorKind::InvalidData, "oversized frame"));
            }
            if self.inbox.len() < 4 + len {
                break;
            }
            out.push(M::decode(&self.inbox[4..4 + len])?);
            self.inbox.drain(..4 + len);
        }
        Ok(out)
    }
}
