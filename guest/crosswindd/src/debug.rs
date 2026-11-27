// SPDX-License-Identifier: AGPL-3.0-or-later
//! Development-only command execution for `crosswindctl exec`. Off unless the kernel command line carries
//! `crosswind.debug=1`, which only a host agent started with CROSSWIND_DEBUG=1 sets.

use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::control_pb as pb;

const MAX_OUTPUT: usize = 256 << 10;
const DEFAULT_TIMEOUT_SECS: u32 = 30;
const MAX_TIMEOUT_SECS: u32 = 600;

pub fn enabled() -> bool {
    std::fs::read_to_string("/proc/cmdline").map(|c| c.split_whitespace().any(|w| w == "crosswind.debug=1")).unwrap_or(false)
}

/// Runs `argv`, killing it after the timeout. Output is stdout then stderr, truncated to the newest `MAX_OUTPUT` bytes.
pub fn exec(argv: &[String], timeout_secs: u32, env: &[(String, String)]) -> pb::DebugExecResult {
    let fail = |text: String| pb::DebugExecResult { exit_code: -1, timed_out: false, output: text.into_bytes() };
    let Some((program, args)) = argv.split_first() else { return fail("empty command".into()) };
    let timeout = Duration::from_secs(u64::from(if timeout_secs == 0 { DEFAULT_TIMEOUT_SECS } else { timeout_secs.min(MAX_TIMEOUT_SECS) }));
    let mut child = match Command::new(program).args(args).envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str()))).process_group(0).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() {
        Ok(child) => child,
        Err(e) => return fail(format!("cannot run {program}: {e}")),
    };
    let readers: Vec<_> = [child.stdout.take().map(|s| Box::new(s) as Box<dyn Read + Send>), child.stderr.take().map(|s| Box::new(s) as Box<dyn Read + Send>)]
        .into_iter()
        .flatten()
        .map(|mut stream| {
            std::thread::spawn(move || {
                let mut buf = Vec::new();
                let _ = stream.read_to_end(&mut buf);
                buf
            })
        })
        .collect();
    let start = Instant::now();
    let (exit_code, timed_out) = loop {
        match child.try_wait() {
            Ok(Some(status)) => break (status.code().unwrap_or(-1), false),
            Ok(None) if start.elapsed() >= timeout => {
                // The command's whole group: grandchildren would otherwise keep the output pipes open.
                unsafe { libc::kill(-(child.id() as i32), libc::SIGKILL) };
                let _ = child.wait();
                break (-1, true);
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(20)),
            Err(_) => break (-1, false),
        }
    };
    let mut output: Vec<u8> = readers.into_iter().flat_map(|r| r.join().unwrap_or_default()).collect();
    if output.len() > MAX_OUTPUT {
        output.drain(..output.len() - MAX_OUTPUT);
    }
    pb::DebugExecResult { exit_code, timed_out, output }
}
