// SPDX-License-Identifier: AGPL-3.0-or-later
//! Wayland protocol handlers: shells, buffers, seat, selection, scale.

use smithay::{
    backend::renderer::utils::on_commit_buffer_handler,
    desktop::PopupKind,
    input::{Seat, SeatHandler, SeatState, pointer::CursorImageStatus},
    reexports::{
        wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode as DecorationMode,
        wayland_server::{
            Client, Resource,
            protocol::{wl_buffer, wl_seat, wl_surface::WlSurface},
        },
    },
    utils::Serial,
    wayland::{
        buffer::BufferHandler,
        compositor::{CompositorClientState, CompositorHandler, CompositorState, get_parent, with_states},
        fractional_scale::{FractionalScaleHandler, with_fractional_scale},
        output::OutputHandler,
        pointer_constraints::PointerConstraintsHandler,
        selection::{
            SelectionHandler, SelectionSource, SelectionTarget,
            data_device::{DataDeviceHandler, DataDeviceState, WaylandDndGrabHandler, set_data_device_focus},
        },
        shell::xdg::{
            PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState,
            XdgToplevelSurfaceData, decoration::XdgDecorationHandler,
        },
        shm::{ShmHandler, ShmState},
    },
};
use smithay::input::dnd::{DnDGrab, DndGrabHandler, GrabType, Source};
use smithay::input::pointer::Focus;

use std::os::fd::OwnedFd;

use crate::{
    clipboard, pb,
    state::{ClientState, Role, State, Win},
};

impl CompositorHandler for State {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        &client.get_data::<ClientState>().expect("client state").compositor_state
    }

    fn new_surface(&mut self, surface: &WlSurface) {
        let scale = self.scale_120 as f64 / 120.0;
        with_states(surface, |states| with_fractional_scale(states, |fs| fs.set_preferred_scale(scale)));
    }

    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
        self.popups.commit(surface);

        if let Some(win) = self.windows.iter().find(|w| &w.surface == surface) {
            match &win.role {
                Role::Toplevel(t) => {
                    let sent = with_states(surface, |s| {
                        s.data_map.get::<XdgToplevelSurfaceData>().expect("xdg data").lock().expect("lock").initial_configure_sent
                    });
                    if !sent {
                        t.send_configure();
                    }
                }
                Role::Popup(p) if !p.is_initial_configure_sent() => {
                    p.send_configure().expect("initial popup configure");
                }
                Role::Popup(_) => {}
            }
        }

        // Subsurface commits dirty the window that owns the tree.
        let mut root = surface.clone();
        while let Some(parent) = get_parent(&root) {
            root = parent;
        }
        if let Some(win) = self.win_by_surface(&root) {
            win.dirty = true;
            let id = win.id;
            self.render_window(id);
        }
    }
}

impl BufferHandler for State {
    fn buffer_destroyed(&mut self, _: &wl_buffer::WlBuffer) {}
}

impl ShmHandler for State {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

impl OutputHandler for State {}
impl PointerConstraintsHandler for State {}

impl FractionalScaleHandler for State {
    fn new_fractional_scale(&mut self, surface: WlSurface) {
        let scale = self.scale_120 as f64 / 120.0;
        with_states(&surface, |states| with_fractional_scale(states, |fs| fs.set_preferred_scale(scale)));
    }
}

impl XdgShellHandler for State {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        let wl = surface.wl_surface().clone();
        self.add_window(Role::Toplevel(surface), wl);
    }

    fn new_popup(&mut self, surface: PopupSurface, _: PositionerState) {
        let wl = surface.wl_surface().clone();
        let _ = self.popups.track_popup(PopupKind::Xdg(surface.clone()));
        self.add_window(Role::Popup(surface), wl);
    }

    fn reposition_request(&mut self, surface: PopupSurface, positioner: PositionerState, token: u32) {
        surface.with_pending_state(|s| {
            s.geometry = positioner.get_geometry();
            s.positioner = positioner;
        });
        surface.send_repositioned(token);
    }

    fn grab(&mut self, _: PopupSurface, _: wl_seat::WlSeat, _: Serial) {}

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        self.remove_window(surface.wl_surface());
    }

    fn popup_destroyed(&mut self, surface: PopupSurface) {
        self.remove_window(surface.wl_surface());
    }

    fn title_changed(&mut self, surface: ToplevelSurface) {
        self.send_changed(surface.wl_surface(), |c, t| c.title = Some(t.title));
    }

    fn app_id_changed(&mut self, surface: ToplevelSurface) {
        self.send_changed(surface.wl_surface(), |c, t| c.app_id = Some(t.app_id));
    }
}

impl XdgDecorationHandler for State {
    fn new_decoration(&mut self, toplevel: ToplevelSurface) {
        // The macOS window supplies the frame.
        toplevel.with_pending_state(|s| s.decoration_mode = Some(DecorationMode::ServerSide));
        toplevel.send_configure();
    }
    fn request_mode(&mut self, toplevel: ToplevelSurface, _: DecorationMode) {
        toplevel.with_pending_state(|s| s.decoration_mode = Some(DecorationMode::ServerSide));
        toplevel.send_pending_configure();
    }
    fn unset_mode(&mut self, toplevel: ToplevelSurface) {
        toplevel.with_pending_state(|s| s.decoration_mode = Some(DecorationMode::ServerSide));
        toplevel.send_pending_configure();
    }
}

impl SeatHandler for State {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Self> {
        &mut self.seat_state
    }

    fn cursor_image(&mut self, _: &Seat<Self>, image: CursorImageStatus) {
        self.send_cursor(image);
    }

    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let dh = &self.display_handle;
        set_data_device_focus(dh, seat, focused.and_then(|s| dh.get_client(s.id()).ok()));
    }
}

impl SelectionHandler for State {
    type SelectionUserData = clipboard::Offered;

    fn new_selection(&mut self, ty: SelectionTarget, source: Option<SelectionSource>, seat: Seat<Self>) {
        // Only client-set clipboard selections reach here; clearing (None) and primary are not forwarded.
        if ty != SelectionTarget::Clipboard {
            return;
        }
        let Some(source) = source else { return };
        clipboard::copy(&seat, &source, self.control.notes_sender());
    }

    fn send_selection(&mut self, _: SelectionTarget, mime_type: String, fd: OwnedFd, seat: Seat<Self>, _: &clipboard::Offered) {
        clipboard::paste(self, &seat, mime_type, fd);
    }
}

impl DataDeviceHandler for State {
    fn data_device_state(&mut self) -> &mut DataDeviceState {
        &mut self.data_device_state
    }
}
impl DndGrabHandler for State {}
impl WaylandDndGrabHandler for State {
    fn dnd_requested<S: Source>(&mut self, source: S, _: Option<WlSurface>, seat: Seat<Self>, serial: Serial, ty: GrabType) {
        if let (GrabType::Pointer, Some(ptr)) = (ty, seat.get_pointer())
            && let Some(start) = ptr.grab_start_data()
        {
            let grab = DnDGrab::new_pointer(&self.display_handle, start, source, seat);
            ptr.set_grab(self, grab, serial, Focus::Keep);
        }
    }
}

impl State {
    fn add_window(&mut self, role: Role, surface: WlSurface) {
        let id = self.next_id;
        self.next_id += 1;
        self.windows.push(Win { id, role, surface, announced: false, dirty: false, in_flight: false, seq: 0, target: None });
    }

    fn remove_window(&mut self, surface: &WlSurface) {
        if let Some(pos) = self.windows.iter().position(|w| &w.surface == surface) {
            let win = self.windows.remove(pos);
            if win.announced {
                self.send(pb::to_host::Msg::Closed(pb::WindowClosed { id: win.id }));
            }
            if self.pointer_window == Some(win.id) {
                self.pointer_window = None;
            }
        }
    }

    fn send_changed(&mut self, surface: &WlSurface, f: impl FnOnce(&mut pb::WindowChanged, ToplevelData)) {
        let Some(win) = self.windows.iter().find(|w| &w.surface == surface) else { return };
        if !win.announced {
            return;
        }
        let id = win.id;
        let data = toplevel_data(surface);
        let mut changed = pb::WindowChanged { id, ..Default::default() };
        f(&mut changed, data);
        self.send(pb::to_host::Msg::Changed(changed));
    }
}

pub struct ToplevelData {
    pub title: String,
    pub app_id: String,
}

pub fn toplevel_data(surface: &WlSurface) -> ToplevelData {
    with_states(surface, |s| {
        let data = s.data_map.get::<XdgToplevelSurfaceData>().expect("xdg data").lock().expect("lock");
        ToplevelData { title: data.title.clone().unwrap_or_default(), app_id: data.app_id.clone().unwrap_or_default() }
    })
}

smithay::delegate_dispatch2!(State);
