// SPDX-License-Identifier: AGPL-3.0-or-later
//! `crosswind-open URL`: the guest's URL handler. Sends the URL to crosswindd, which opens it on
//! the macOS host. `/usr/bin/xdg-open` execs this binary (busybox nc has no unix-socket mode).

use std::{
    io::{BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    process::ExitCode,
    time::Duration,
};

const SOCKET_PATH: &str = "/run/crosswind/open-url.sock";

fn main() -> ExitCode {
    let Some(url) = std::env::args().nth(1) else {
        eprintln!("usage: crosswind-open URL");
        return ExitCode::from(2);
    };
    match open(&url) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("crosswind-open: {e}");
            ExitCode::FAILURE
        }
    }
}

fn open(url: &str) -> Result<(), String> {
    let mut stream = UnixStream::connect(SOCKET_PATH).map_err(|e| format!("connect {SOCKET_PATH}: {e}"))?;
    stream.set_read_timeout(Some(Duration::from_secs(35))).map_err(|e| e.to_string())?;
    writeln!(stream, "{url}").map_err(|e| format!("send: {e}"))?;
    let mut status = String::new();
    BufReader::new(&stream).read_line(&mut status).map_err(|e| format!("read: {e}"))?;
    match status.trim_end() {
        "ok" => Ok(()),
        other => Err(other.strip_prefix("err ").unwrap_or(other).to_owned()),
    }
}
