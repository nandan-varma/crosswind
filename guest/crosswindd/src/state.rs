// SPDX-License-Identifier: AGPL-3.0-or-later
use std::{ffi::OsString, sync::Arc, time::Instant};

use smithay::{
    backend::renderer::{damage::OutputDamageTracker, pixman::PixmanRenderer},
    desktop::PopupManager,
    input::{Seat, SeatState},
    output::{Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, Interest, LoopHandle, LoopSignal, Mode, PostAction, RegistrationToken, generic::Generic},
        wayland_server::{
            Display, DisplayHandle,
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::wl_surface::WlSurface,
        },
    },
    wayland::{
        compositor::{CompositorClientState, CompositorState},
        fractional_scale::FractionalScaleManagerState,
        output::OutputManagerState,
        selection::data_device::DataDeviceState,
        shell::xdg::{ToplevelSurface, XdgShellState, decoration::XdgDecorationState},
        shm::ShmState,
        socket::ListeningSocketSource,
        viewporter::ViewporterState,
    },
};

use crate::{link::Link, pb};

pub enum Role {
    Toplevel(ToplevelSurface),
    Popup(smithay::wayland::shell::xdg::PopupSurface),
}

/// One host window: an xdg toplevel or popup and its render target.
pub struct Win {
    pub id: u32,
    pub role: Role,
    pub surface: WlSurface,
    pub announced: bool,
    pub dirty: bool,
    /// A frame is on the wire and not yet acknowledged by the host.
    pub in_flight: bool,
    pub seq: u64,
    pub target: Option<Target>,
}

pub struct Target {
    pub image: smithay::reexports::pixman::Image<'static, 'static>,
    pub tracker: OutputDamageTracker,
    pub size: (i32, i32),
    pub scale_120: u32,
    pub first: bool,
}

pub struct State {
    pub start_time: Instant,
    pub socket_name: OsString,
    pub display_handle: DisplayHandle,
    pub loop_handle: LoopHandle<'static, State>,
    pub loop_signal: LoopSignal,

    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub xdg_decoration_state: XdgDecorationState,
    pub shm_state: ShmState,
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<State>,
    pub data_device_state: DataDeviceState,
    pub fractional_scale_state: FractionalScaleManagerState,
    pub viewporter_state: ViewporterState,
    pub popups: PopupManager,
    pub seat: Seat<State>,
    pub output: Output,

    pub renderer: PixmanRenderer,
    pub windows: Vec<Win>,
    pub next_id: u32,
    pub scale_120: u32,
    pub link: Link,
    pub pointer_window: Option<u32>,
    write_token: Option<RegistrationToken>,
}

#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _: ClientId) {}
    fn disconnected(&self, _: ClientId, _: DisconnectReason) {}
}

impl State {
    pub fn new(event_loop: &mut EventLoop<'static, Self>, display: Display<Self>, link: Link) -> Self {
        let dh = display.handle();
        let loop_handle = event_loop.handle();

        let mut seat_state = SeatState::new();
        let mut seat = seat_state.new_wl_seat(&dh, "seat0");
        seat.add_keyboard(Default::default(), 600, 25).expect("default xkb keymap");
        seat.add_pointer();

        let output = Output::new(
            "crosswind".into(),
            PhysicalProperties { size: (0, 0).into(), subpixel: Subpixel::Unknown, make: "Crosswind".into(), model: "Host".into(), serial_number: "0".into() },
        );
        output.create_global::<Self>(&dh);

        let socket = ListeningSocketSource::new_auto().expect("wayland socket");
        let socket_name = socket.socket_name().to_os_string();
        loop_handle
            .insert_source(socket, |stream, _, state| {
                state.display_handle.insert_client(stream, Arc::new(ClientState::default())).ok();
            })
            .expect("wayland listener");
        loop_handle
            .insert_source(Generic::new(display, Interest::READ, Mode::Level), |_, display, state| {
                // Safety: the display is never dropped while the loop runs.
                unsafe { display.get_mut().dispatch_clients(state).expect("dispatch") };
                Ok(PostAction::Continue)
            })
            .expect("display source");

        let read_fd = link.fd().try_clone_to_owned().expect("dup vsock fd");
        loop_handle
            .insert_source(Generic::new(read_fd, Interest::READ, Mode::Level), |_, _, state| {
                state.on_host_readable();
                Ok(PostAction::Continue)
            })
            .expect("host source");

        Self {
            start_time: Instant::now(),
            socket_name,
            loop_signal: event_loop.get_signal(),
            compositor_state: CompositorState::new::<Self>(&dh),
            xdg_shell_state: XdgShellState::new::<Self>(&dh),
            xdg_decoration_state: XdgDecorationState::new::<Self>(&dh),
            shm_state: ShmState::new::<Self>(&dh, vec![]),
            output_manager_state: OutputManagerState::new_with_xdg_output::<Self>(&dh),
            data_device_state: DataDeviceState::new::<Self>(&dh),
            fractional_scale_state: FractionalScaleManagerState::new::<Self>(&dh),
            viewporter_state: ViewporterState::new::<Self>(&dh),
            popups: PopupManager::default(),
            seat_state,
            seat,
            output,
            renderer: PixmanRenderer::new().expect("pixman renderer"),
            windows: Vec::new(),
            next_id: 1,
            scale_120: 120,
            link,
            pointer_window: None,
            write_token: None,
            display_handle: dh,
            loop_handle,
        }
    }

    pub fn send(&mut self, msg: pb::to_host::Msg) {
        self.link.send(&pb::ToHost { msg: Some(msg) });
    }

    /// Called once per loop iteration: push queued bytes to the host and release clients.
    pub fn flush(&mut self) {
        if let Err(e) = self.link.flush() {
            tracing::error!("host link lost: {e}");
            self.loop_signal.stop();
        }
        if self.link.wants_write() && self.write_token.is_none() {
            let fd = self.link.fd().try_clone_to_owned().expect("dup vsock fd");
            let token = self
                .loop_handle
                .insert_source(Generic::new(fd, Interest::WRITE, Mode::Level), |_, _, state| {
                    if let Err(e) = state.link.flush() {
                        tracing::error!("host link lost: {e}");
                        state.loop_signal.stop();
                    }
                    if state.link.wants_write() {
                        Ok(PostAction::Continue)
                    } else {
                        state.write_token = None;
                        Ok(PostAction::Remove)
                    }
                })
                .expect("write source");
            self.write_token = Some(token);
        }
        let _ = self.display_handle.flush_clients();
    }

    pub fn win_by_surface(&mut self, surface: &WlSurface) -> Option<&mut Win> {
        self.windows.iter_mut().find(|w| &w.surface == surface)
    }

    pub fn win_by_id(&mut self, id: u32) -> Option<&mut Win> {
        self.windows.iter_mut().find(|w| w.id == id)
    }
}
