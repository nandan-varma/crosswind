// SPDX-License-Identifier: AGPL-3.0-or-later
//! Supervises `xwayland-satellite`, which gives X11 clients a rootless Xwayland on our compositor.
//! The child is restarted with backoff whenever it exits.

use std::{
    process::{Child, Command},
    thread,
    time::{Duration, Instant},
};

/// The X display number satellite serves. Apps get it as DISPLAY.
pub const DISPLAY: &str = ":0";

const BACKOFF_MIN: Duration = Duration::from_secs(1);
const BACKOFF_MAX: Duration = Duration::from_secs(30);
/// A child that ran at least this long counts as healthy, so the backoff resets.
const HEALTHY_AFTER: Duration = Duration::from_secs(10);

/// Starts the supervisor thread. `wayland_socket` is the name of our compositor socket inside `runtime_dir`.
/// The X socket directory (`X11_UNIX_DIR`) is created root-owned and sticky by the image's crosswind-data service.
pub fn supervise(wayland_socket: String, runtime_dir: String) {
    thread::Builder::new()
        .name("xwayland-satellite".into())
        .spawn(move || run_forever(&wayland_socket, &runtime_dir))
        .expect("satellite supervisor thread");
}

fn run_forever(wayland_socket: &str, runtime_dir: &str) {
    let mut backoff = BACKOFF_MIN;
    loop {
        let started = Instant::now();
        match spawn(wayland_socket, runtime_dir) {
            Ok(mut child) => {
                let status = child.wait();
                tracing::warn!(?status, "xwayland-satellite exited");
            }
            Err(e) => tracing::error!(error = %e, "cannot start xwayland-satellite"),
        }
        if started.elapsed() >= HEALTHY_AFTER {
            backoff = BACKOFF_MIN;
        }
        thread::sleep(backoff);
        backoff = (backoff * 2).min(BACKOFF_MAX);
    }
}

fn spawn(wayland_socket: &str, runtime_dir: &str) -> std::io::Result<Child> {
    Command::new("/usr/bin/xwayland-satellite")
        .arg(DISPLAY)
        .env("WAYLAND_DISPLAY", wayland_socket)
        .env("XDG_RUNTIME_DIR", runtime_dir)
        .spawn()
}
