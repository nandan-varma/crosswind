// SPDX-License-Identifier: AGPL-3.0-or-later
//! Messages from the host: configure, acknowledgements, input, close.

use smithay::{
    backend::input::{Axis, AxisSource, ButtonState, InputTime, KeyState},
    desktop::{WindowSurfaceType, utils::under_from_surface_tree},
    input::{
        keyboard::{FilterResult, Keycode},
        pointer::{AxisFrame, ButtonEvent, MotionEvent},
    },
    output::{Mode, Scale},
    reexports::{
        wayland_protocols::xdg::shell::server::xdg_toplevel,
        wayland_server::protocol::wl_surface::WlSurface,
    },
    utils::{SERIAL_COUNTER, Size},
    wayland::{compositor::{with_surface_tree_downward, TraversalAction}, fractional_scale::with_fractional_scale},
};
use smithay::wayland::compositor::SurfaceData;

use crate::{
    pb::{self, input::Event, to_guest::Msg},
    render::geometry,
    state::{Role, State},
};

impl State {
    pub fn on_host_readable(&mut self) {
        match self.link.recv::<pb::ToGuest>() {
            Ok(messages) => {
                for m in messages.into_iter().filter_map(|m| m.msg) {
                    self.on_host_message(m);
                }
            }
            Err(e) => {
                tracing::error!("host link lost: {e}");
                self.loop_signal.stop();
            }
        }
    }

    fn on_host_message(&mut self, msg: Msg) {
        match msg {
            Msg::Output(o) => self.set_output(o),
            Msg::Configure(c) => self.configure(c),
            Msg::Ack(a) => self.on_ack(a.window, a.seq),
            Msg::Close(c) => {
                if let Some(Role::Toplevel(t)) = self.win_by_id(c.window).map(|w| &w.role) {
                    t.send_close();
                }
            }
            Msg::Input(i) => self.input(i),
        }
    }

    fn set_output(&mut self, o: pb::Output) {
        self.scale_120 = o.scale_120.max(120);
        let scale = self.scale_120 as f64 / 120.0;
        let physical: Size<i32, _> = (((o.width as f64) * scale).round() as i32, ((o.height as f64) * scale).round() as i32).into();
        self.output.change_current_state(
            Some(Mode { size: physical, refresh: o.refresh_mhz as i32 }),
            None,
            Some(Scale::Fractional(scale)),
            Some((0, 0).into()),
        );
        self.output.set_preferred(Mode { size: physical, refresh: o.refresh_mhz as i32 });
        let surfaces: Vec<WlSurface> = self.windows.iter().map(|w| w.surface.clone()).collect();
        for s in surfaces {
            set_preferred_scale_tree(&s, scale);
        }
        let ids: Vec<u32> = self.windows.iter().map(|w| w.id).collect();
        for id in ids {
            self.render_window(id);
        }
    }

    fn configure(&mut self, c: pb::Configure) {
        let Some(win) = self.windows.iter().find(|w| w.id == c.window) else { return };
        let Role::Toplevel(t) = &win.role else { return };
        let surface = win.surface.clone();
        t.with_pending_state(|s| {
            s.size = (c.width > 0 && c.height > 0).then(|| (c.width as i32, c.height as i32).into());
            for (flag, state) in [
                (c.activated, xdg_toplevel::State::Activated),
                (c.fullscreen, xdg_toplevel::State::Fullscreen),
                (c.maximized, xdg_toplevel::State::Maximized),
            ] {
                if flag { s.states.set(state); } else { s.states.unset(state); }
            }
        });
        t.send_pending_configure();
        if c.activated {
            let kb = self.seat.get_keyboard().expect("keyboard");
            kb.set_focus(self, Some(surface), SERIAL_COUNTER.next_serial());
        }
    }

    fn input(&mut self, input: pb::Input) {
        tracing::debug!(?input, "input");
        let Some(win) = self.windows.iter().find(|w| w.id == input.window) else { return };
        let surface = win.surface.clone();
        let Some(event) = input.event else { return };
        let ptr = self.seat.get_pointer().expect("pointer");
        let kb = self.seat.get_keyboard().expect("keyboard");
        let serial = SERIAL_COUNTER.next_serial();
        match event {
            Event::Motion(m) => {
                let geo = geometry(&surface);
                let at = (m.x + geo.loc.x as f64, m.y + geo.loc.y as f64).into();
                let focus = under_from_surface_tree(&surface, at, (0, 0), WindowSurfaceType::ALL)
                    .map(|(s, origin)| (s, origin.to_f64()));
                self.pointer_window = Some(input.window);
                ptr.motion(self, focus, &MotionEvent { location: at, serial, time: InputTime::from_millis(m.time_ms) });
                ptr.frame(self);
            }
            Event::Button(b) => {
                let state = if b.pressed { ButtonState::Pressed } else { ButtonState::Released };
                ptr.button(self, &ButtonEvent { button: b.button, state, serial, time: InputTime::from_millis(b.time_ms) });
                ptr.frame(self);
            }
            Event::Axis(a) => {
                let mut frame = AxisFrame::new(InputTime::from_millis(a.time_ms)).source(AxisSource::Finger);
                frame = frame.value(Axis::Horizontal, a.dx).value(Axis::Vertical, a.dy);
                if a.finished {
                    frame = frame.stop(Axis::Horizontal).stop(Axis::Vertical);
                }
                ptr.axis(self, frame);
                ptr.frame(self);
            }
            Event::Leave(_) => {
                ptr.motion(self, None, &MotionEvent { location: ptr.current_location(), serial, time: InputTime::from_millis(0) });
                ptr.frame(self);
            }
            Event::Key(k) => {
                let state = if k.pressed { KeyState::Pressed } else { KeyState::Released };
                // xkb keycodes are evdev codes offset by 8.
                kb.input::<(), _>(self, Keycode::new(k.keycode + 8), state, serial, InputTime::from_millis(k.time_ms), |_, _, _| FilterResult::Forward);
            }
        }
    }
}

fn set_preferred_scale_tree(root: &WlSurface, scale: f64) {
    with_surface_tree_downward(
        root,
        (),
        |_, _, _| TraversalAction::DoChildren(()),
        |_, states: &SurfaceData, _| with_fractional_scale(states, |fs| fs.set_preferred_scale(scale)),
        |_, _, _| true,
    );
}
