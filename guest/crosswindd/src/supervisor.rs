// SPDX-License-Identifier: AGPL-3.0-or-later
//! Keeps a child process running: a supervisor thread restarts it with backoff whenever it exits.

use std::{
    process::{Child, Command},
    thread,
    time::{Duration, Instant},
};

const BACKOFF_MIN: Duration = Duration::from_secs(1);
const BACKOFF_MAX: Duration = Duration::from_secs(30);
/// A child that ran at least this long counts as healthy, so the backoff resets.
const HEALTHY_AFTER: Duration = Duration::from_secs(10);

/// Starts a supervisor thread named `name` that runs `program` with `args` and `env` added to the inherited environment.
pub fn supervise(name: &'static str, program: &'static str, args: Vec<String>, env: Vec<(String, String)>) {
    thread::Builder::new()
        .name(name.into())
        .spawn(move || run_forever(name, program, &args, &env))
        .expect("supervisor thread");
}

fn run_forever(name: &str, program: &str, args: &[String], env: &[(String, String)]) {
    let mut backoff = BACKOFF_MIN;
    loop {
        let started = Instant::now();
        match spawn(program, args, env) {
            Ok(mut child) => {
                let status = child.wait();
                tracing::warn!(process = name, ?status, "exited");
            }
            Err(e) => tracing::error!(process = name, error = %e, "cannot start"),
        }
        if started.elapsed() >= HEALTHY_AFTER {
            backoff = BACKOFF_MIN;
        }
        thread::sleep(backoff);
        backoff = (backoff * 2).min(BACKOFF_MAX);
    }
}

fn spawn(program: &str, args: &[String], env: &[(String, String)]) -> std::io::Result<Child> {
    Command::new(program).args(args).envs(env.iter().map(|(k, v)| (k, v))).spawn()
}
