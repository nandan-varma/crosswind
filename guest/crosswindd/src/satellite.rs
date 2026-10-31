// SPDX-License-Identifier: AGPL-3.0-or-later
//! Supervises `xwayland-satellite`, which gives X11 clients a rootless Xwayland on our compositor.
//! The child is restarted with backoff whenever it exits.

use crate::supervisor;

/// The X display number satellite serves. Apps get it as DISPLAY.
pub const DISPLAY: &str = ":0";

/// Starts the supervisor thread. `wayland_socket` is the name of our compositor socket inside `runtime_dir`.
/// The X socket directory (`X11_UNIX_DIR`) is created root-owned and sticky by the image's crosswind-data service.
pub fn supervise(wayland_socket: String, runtime_dir: String) {
    supervisor::supervise(
        "xwayland-satellite",
        "/usr/bin/xwayland-satellite",
        vec![DISPLAY.to_owned()],
        vec![("WAYLAND_DISPLAY".to_owned(), wayland_socket), ("XDG_RUNTIME_DIR".to_owned(), runtime_dir)],
    );
}
