// SPDX-License-Identifier: AGPL-3.0-or-later
//! Audio for Linux apps: PipeWire, its session manager, and the PulseAudio server that Flatpak's
//! `--socket=pulseaudio` connects to. Each runs as a supervised child in the user session. The daemons retry
//! until PipeWire's socket exists, so start order does not matter.

use crate::supervisor;

/// Starts the audio stack. `runtime_dir` is XDG_RUNTIME_DIR; pipewire-pulse creates `pulse/native` inside it.
pub fn start(runtime_dir: &str) {
    let env = vec![("XDG_RUNTIME_DIR".to_owned(), runtime_dir.to_owned())];
    supervisor::supervise("pipewire", "/usr/bin/pipewire", Vec::new(), env.clone());
    supervisor::supervise("wireplumber", "/usr/bin/wireplumber", Vec::new(), env.clone());
    supervisor::supervise("pipewire-pulse", "/usr/bin/pipewire-pulse", Vec::new(), env);
}
