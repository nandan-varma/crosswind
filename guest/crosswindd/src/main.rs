// SPDX-License-Identifier: AGPL-3.0-or-later
//! crosswindd: a headless Wayland compositor that mirrors each client window to the macOS host.

mod control;
mod flatpak;
mod handlers;
mod host;
mod link;
mod render;
mod state;

pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/crosswind.display.rs"));
}

pub mod control_pb {
    include!(concat!(env!("OUT_DIR"), "/crosswind.control.rs"));
}

use smithay::reexports::{calloop::EventLoop, wayland_server::Display};

/// vsock port the host listens on for the display channel.
const DISPLAY_PORT: u32 = 5000;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let mut event_loop: EventLoop<state::State> = EventLoop::try_new()?;
    let display: Display<state::State> = Display::new()?;
    let link = link::Link::connect(DISPLAY_PORT)?;
    let control_link = link::Link::connect(control::CONTROL_PORT)?;
    let session_bus = control::session_bus()?;
    let mut state = state::State::new(&mut event_loop, display, link, control_link, session_bus);
    tracing::info!(socket = ?state.socket_name, "compositor ready");

    event_loop.run(None, &mut state, |state| state.flush())?;
    Ok(())
}
