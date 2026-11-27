// SPDX-License-Identifier: AGPL-3.0-or-later
//! Audio for Linux apps: PipeWire, its session manager, and the PulseAudio server that Flatpak's
//! `--socket=pulseaudio` connects to. Each runs as a supervised child in the user session. The daemons retry
//! until PipeWire's socket exists, so start order does not matter.

use std::fs;
use std::path::Path;

use crate::supervisor;

/// PipeWire reads `pipewire/pipewire.conf.d` below `XDG_CONFIG_HOME`; this one is writable at run time.
const CONFIG_HOME: &str = "/run/crosswind/config";

const MICROPHONE_CONF: &str = r#"context.objects = [
    {   factory = adapter
        args = {
            factory.name     = api.alsa.pcm.source
            node.name        = "crosswind.input"
            node.description = "Mac Microphone"
            media.class      = "Audio/Source"
            api.alsa.path    = "hw:0,1"
            audio.position   = [ FL FR ]
        }
    }
]
"#;

/// True when the VM exports a capture stream, which it does only while the microphone is enabled on the Mac.
fn has_capture(pcm_list: &str) -> bool {
    pcm_list.lines().any(|line| line.contains("capture"))
}

/// Declares the microphone source only when the capture stream exists: a source PipeWire cannot create stops it from
/// starting at all, and output would die with it. Returns the extra environment for PipeWire.
fn microphone_config() -> Vec<(String, String)> {
    let present = fs::read_to_string("/proc/asound/pcm").is_ok_and(|list| has_capture(&list));
    let dir = Path::new(CONFIG_HOME).join("pipewire/pipewire.conf.d");
    let written = present
        && fs::create_dir_all(&dir).is_ok()
        && fs::write(dir.join("20-crosswind-microphone.conf"), MICROPHONE_CONF).is_ok();
    if written { vec![("XDG_CONFIG_HOME".to_owned(), CONFIG_HOME.to_owned())] } else { Vec::new() }
}

/// Starts the audio stack. `runtime_dir` is XDG_RUNTIME_DIR; pipewire-pulse creates `pulse/native` inside it.
pub fn start(runtime_dir: &str) {
    let env = vec![("XDG_RUNTIME_DIR".to_owned(), runtime_dir.to_owned())];
    let mut pipewire_env = env.clone();
    pipewire_env.extend(microphone_config());
    supervisor::supervise("pipewire", "/usr/bin/pipewire", Vec::new(), pipewire_env);
    supervisor::supervise("wireplumber", "/usr/bin/wireplumber", Vec::new(), env.clone());
    supervisor::supervise("pipewire-pulse", "/usr/bin/pipewire-pulse", Vec::new(), env);
}

#[cfg(test)]
mod tests {
    use super::has_capture;

    #[test]
    fn capture_is_detected_from_the_pcm_list() {
        let both = "00-00: virtio-snd : VirtIO PCM 0 : playback 1\n00-01: virtio-snd : VirtIO PCM 1 : capture 1\n";
        assert!(has_capture(both));
        assert!(!has_capture("00-00: virtio-snd : VirtIO PCM 0 : playback 1\n"));
        assert!(!has_capture(""));
    }
}
