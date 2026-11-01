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
    limits,
    pb::{self, input::Event, to_guest::Msg},
    render::geometry,
    state::{Role, State},
};

/// Largest xkb-offset-free evdev keycode: xkb codes are evdev + 8 and must stay within one byte.
const MAX_KEYCODE: u32 = 255 - 8;

/// The host display mode after validation: physical size, buffer scale and refresh rate.
#[derive(Debug, PartialEq)]
pub struct OutputMode {
    pub scale_120: u32,
    pub physical: (i32, i32),
    pub refresh_mhz: i32,
}

/// Validates the host's display description. `None` when the size or scale is outside the limits (the previous
/// mode then stays in effect).
pub fn output_mode(o: &pb::Output) -> Option<OutputMode> {
    let scale_120 = o.scale_120.clamp(limits::SCALE_120_MIN, limits::SCALE_120_MAX);
    let scale = scale_120 as f64 / 120.0;
    let pw = (o.width as f64 * scale).round() as u32;
    let ph = (o.height as f64 * scale).round() as u32;
    if !limits::surface_ok(pw, ph, scale_120) {
        return None;
    }
    Some(OutputMode {
        scale_120,
        physical: (pw as i32, ph as i32),
        refresh_mhz: o.refresh_mhz.min(i32::MAX as u32) as i32,
    })
}

/// A size the client may be configured to, or `None` for "client's choice".
pub fn configure_size(c: &pb::Configure) -> Option<(i32, i32)> {
    let ok = c.width > 0 && c.height > 0 && c.width <= limits::MAX_SIDE && c.height <= limits::MAX_SIDE;
    ok.then(|| (c.width as i32, c.height as i32))
}

/// Input whose numbers can be used: finite coordinates and deltas, keycodes that fit xkb.
pub fn input_is_sane(event: &Event) -> bool {
    match event {
        Event::Motion(m) => limits::finite(m.x) && limits::finite(m.y),
        Event::Axis(a) => limits::finite(a.dx) && limits::finite(a.dy),
        Event::Key(k) => k.keycode <= MAX_KEYCODE,
        Event::Button(_) | Event::Leave(_) => true,
    }
}

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
                let found = self.win_by_id(c.window).map(|w| matches!(w.role, Role::Toplevel(_)));
                tracing::info!("DBG close window={} found={:?}", c.window, found);  // DEBUG-TEMP
                if let Some(Role::Toplevel(t)) = self.win_by_id(c.window).map(|w| &w.role) {
                    t.send_close();
                }
            }
            Msg::Input(i) => self.input(i),
        }
    }

    fn set_output(&mut self, o: pb::Output) {
        let Some(mode) = output_mode(&o) else {
            tracing::warn!(width = o.width, height = o.height, scale = o.scale_120, "host output refused");
            return;
        };
        self.scale_120 = mode.scale_120;
        let scale = self.scale_120 as f64 / 120.0;
        let physical: Size<i32, _> = mode.physical.into();
        self.output.change_current_state(
            Some(Mode { size: physical, refresh: mode.refresh_mhz }),
            None,
            Some(Scale::Fractional(scale)),
            Some((0, 0).into()),
        );
        self.output.set_preferred(Mode { size: physical, refresh: mode.refresh_mhz });
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
        let size = configure_size(&c);
        t.with_pending_state(|s| {
            s.size = size.map(Into::into);
            for (flag, state) in [
                (c.activated, xdg_toplevel::State::Activated),
                (c.fullscreen, xdg_toplevel::State::Fullscreen),
                (c.maximized, xdg_toplevel::State::Maximized),
            ] {
                if flag { s.states.set(state); } else { s.states.unset(state); }
            }
        });
        t.send_pending_configure();
        if c.activated
            && let Some(kb) = self.seat.get_keyboard()
        {
            kb.set_focus(self, Some(surface), SERIAL_COUNTER.next_serial());
        }
    }

    fn input(&mut self, input: pb::Input) {
        tracing::debug!(?input, "input");
        let Some(win) = self.windows.iter().find(|w| w.id == input.window) else { return };
        let surface = win.surface.clone();
        let Some(event) = input.event else { return };
        if !input_is_sane(&event) {
            tracing::warn!("host input refused: non-finite or out-of-range value");
            return;
        }
        let (Some(ptr), Some(kb)) = (self.seat.get_pointer(), self.seat.get_keyboard()) else { return };
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::limits;
    use prost::Message;

    fn output(width: u32, height: u32, scale_120: u32, refresh_mhz: u32) -> pb::Output {
        pb::Output { width, height, scale_120, refresh_mhz }
    }

    #[test]
    fn output_edges() {
        assert_eq!(output_mode(&output(1280, 800, 240, 60000)).unwrap().physical, (2560, 1600));
        assert!(output_mode(&output(0, 800, 120, 60000)).is_none());
        assert!(output_mode(&output(20_000, 800, 120, 60000)).is_none());
        assert!(output_mode(&output(16_384, 4096, 120, 60000)).is_some());
        // Scale is clamped into [60, 960] before the size check, so a huge scale cannot overflow the size.
        assert_eq!(output_mode(&output(100, 100, u32::MAX, 0)).unwrap().scale_120, limits::SCALE_120_MAX);
        assert_eq!(output_mode(&output(100, 100, 0, u32::MAX)).unwrap().refresh_mhz, i32::MAX);
    }

    #[test]
    fn configure_sizes_are_bounded() {
        let c = |width, height| pb::Configure { window: 1, width, height, ..Default::default() };
        assert_eq!(configure_size(&c(800, 600)), Some((800, 600)));
        assert_eq!(configure_size(&c(0, 600)), None);
        assert_eq!(configure_size(&c(u32::MAX, 600)), None);
        assert_eq!(configure_size(&c(16_385, 1)), None);
    }

    #[test]
    fn non_finite_input_is_refused() {
        assert!(input_is_sane(&Event::Motion(pb::PointerMotion { x: 1.0, y: 2.0, time_ms: 0 })));
        assert!(!input_is_sane(&Event::Motion(pb::PointerMotion { x: f64::NAN, y: 0.0, time_ms: 0 })));
        assert!(!input_is_sane(&Event::Motion(pb::PointerMotion { x: 0.0, y: f64::INFINITY, time_ms: 0 })));
        assert!(!input_is_sane(&Event::Axis(pb::PointerAxis { dx: f64::NEG_INFINITY, dy: 0.0, finished: false, time_ms: 0 })));
        assert!(input_is_sane(&Event::Key(pb::Key { keycode: MAX_KEYCODE, pressed: true, time_ms: 0 })));
        assert!(!input_is_sane(&Event::Key(pb::Key { keycode: u32::MAX, pressed: true, time_ms: 0 })));
    }

    /// Random bytes through the protobuf decoder, then every host message type through the validators: nothing may
    /// panic, and an accepted output always has a surface the limits allow.
    #[test]
    fn random_host_messages_never_panic() {
        let mut state = 0xDEAD_BEEF_u64;
        for _ in 0..30_000 {
            let len = (limits::xorshift(&mut state) % 96) as usize;
            let bytes: Vec<u8> = (0..len).map(|_| limits::xorshift(&mut state) as u8).collect();
            let Ok(msg) = pb::ToGuest::decode(bytes.as_slice()) else { continue };
            match msg.msg {
                Some(Msg::Output(o)) => {
                    if let Some(mode) = output_mode(&o) {
                        assert!(limits::surface_ok(mode.physical.0 as u32, mode.physical.1 as u32, mode.scale_120));
                    }
                }
                Some(Msg::Configure(c)) => {
                    if let Some((w, h)) = configure_size(&c) {
                        assert!(w > 0 && h > 0 && w as u32 <= limits::MAX_SIDE && h as u32 <= limits::MAX_SIDE);
                    }
                }
                Some(Msg::Input(i)) => {
                    if let Some(event) = i.event {
                        let _ = input_is_sane(&event);
                    }
                }
                _ => {}
            }
        }
    }
}
