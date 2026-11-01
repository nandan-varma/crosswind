// SPDX-License-Identifier: AGPL-3.0-or-later
//! Messages from the host: configure, acknowledgements, input, close.

use smithay::{
    backend::input::{Axis, AxisSource, ButtonState, InputTime, KeyState},
    desktop::{WindowSurfaceType, utils::under_from_surface_tree},
    input::{
        keyboard::{FilterResult, Keycode, XkbConfig},
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
use smithay::wayland::text_input::TextInputSeat;

use crate::{
    limits,
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
                match self.win_by_id(c.window).map(|w| &w.role) {
                    Some(Role::Toplevel(t)) => t.send_close(),
                    // The host dismisses a menu when its parent loses focus: the client gets popup_done.
                    Some(Role::Popup(p)) => p.send_popup_done(),
                    None => {}
                }
            }
            Msg::Input(i) => self.input(i),
            Msg::KeyboardLayout(l) => self.set_keyboard_layout(l),
            Msg::TextInput(t) => self.text_input(t),
        }
    }

    fn set_output(&mut self, o: pb::Output) {
        if o.width == 0 || o.height == 0 || o.width > limits::MAX_SIDE || o.height > limits::MAX_SIDE {
            return;
        }
        self.scale_120 = o.scale_120.clamp(limits::SCALE_120_MIN.max(120), limits::SCALE_120_MAX);
        let scale = self.scale_120 as f64 / 120.0;
        let physical: Size<i32, _> = (((o.width as f64) * scale).round() as i32, ((o.height as f64) * scale).round() as i32).into();
        self.output.change_current_state(
            Some(Mode { size: physical, refresh: o.refresh_mhz as i32 }),
            None,
            Some(Scale::Fractional(scale)),
            Some((0, 0).into()),
        );
        self.output.set_preferred(Mode { size: physical, refresh: o.refresh_mhz as i32 });
        // Toplevels follow their own scale from Configure; only popups (which never get one) track the default.
        let popups: Vec<(u32, WlSurface)> = self
            .windows
            .iter()
            .filter(|w| matches!(w.role, Role::Popup(_)))
            .map(|w| (w.id, w.surface.clone()))
            .collect();
        let default_120 = self.scale_120;
        for (id, surface) in popups {
            set_preferred_scale_tree(&surface, scale);
            if let Some(win) = self.win_by_id(id) {
                win.scale_120 = default_120;
            }
            self.render_window(id);
        }
    }

    /// The host's backing scale for one window; it changes when the window moves between displays.
    fn apply_window_scale(&mut self, id: u32, scale_120: u32) {
        if !(limits::SCALE_120_MIN..=limits::SCALE_120_MAX).contains(&scale_120) {
            return;
        }
        let Some(win) = self.win_by_id(id) else { return };
        if win.scale_120 == scale_120 {
            return;
        }
        win.scale_120 = scale_120;
        let surface = win.surface.clone();
        set_preferred_scale_tree(&surface, scale_120 as f64 / 120.0);
        self.render_window(id);
    }

    fn configure(&mut self, c: pb::Configure) {
        if c.width > limits::MAX_SIDE || c.height > limits::MAX_SIDE {
            return;
        }
        let c = pb::Configure { scale_120: c.scale_120.clamp(limits::SCALE_120_MIN, limits::SCALE_120_MAX), ..c };
        self.apply_window_scale(c.window, c.scale_120);
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

    /// Rebuilds the seat keymap for the host's layout. Key codes are physical, so only the characters change; the
    /// repeat rate and delay on the keyboard handle are kept.
    fn set_keyboard_layout(&mut self, l: pb::KeyboardLayout) {
        let Some((layout, variant)) = xkb_names(&l) else {
            tracing::warn!("host keyboard layout refused: not an xkb name");
            return;
        };
        let Some(kb) = self.seat.get_keyboard() else { return };
        let config = XkbConfig { layout: &layout, variant: &variant, ..Default::default() };
        if let Err(e) = kb.set_xkb_config(self, config) {
            tracing::warn!("xkb keymap {layout}/{variant} failed: {e}");
        }
    }

    /// Applies the host's composition result to the client that has text input focus. Dropped unless `window` is
    /// the focused window, so a late update cannot land in another client.
    fn text_input(&mut self, t: pb::TextInput) {
        let text_input = self.seat.text_input().clone();
        let Some(focus) = text_input.focus() else { return };
        if self.win_by_surface(&focus).map(|w| w.id) != Some(t.window) {
            tracing::debug!("text input for window {} dropped: not focused", t.window);
            return;
        }
        text_input.with_active_text_input(|ti, _| {
            if let Some(d) = &t.delete_surrounding {
                ti.delete_surrounding_text(d.before, d.after);
            }
            if let Some(c) = &t.commit {
                ti.commit_string((!c.text.is_empty()).then(|| c.text.clone()));
            }
            if let Some(p) = &t.preedit {
                let text = (!p.text.is_empty()).then(|| p.text.clone());
                let (begin, end) = preedit_cursor(&p.text, p.cursor_begin, p.cursor_end)
                    .unwrap_or((p.text.len() as i32, p.text.len() as i32));
                ti.preedit_string(text, begin, end);
            }
        });
        text_input.done(false);
    }

    fn input(&mut self, input: pb::Input) {
        tracing::debug!(?input, "input");
        let Some(win) = self.windows.iter().find(|w| w.id == input.window) else { return };
        let surface = win.surface.clone();
        let Some(event) = input.event else { return };
        let sane = match &event {
            Event::Motion(m) => limits::finite(m.x) && limits::finite(m.y),
            Event::Axis(a) => limits::finite(a.dx) && limits::finite(a.dy),
            _ => true,
        };
        if !sane {
            return;
        }
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

/// XKB layout and variant names from the host. Empty layout means "us". `None` when a name is not a plain XKB
/// identifier, so the current keymap stays.
pub fn xkb_names(l: &pb::KeyboardLayout) -> Option<(String, String)> {
    let plain = |s: &str| s.len() <= 32 && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
    let layout = if l.layout.is_empty() { "us" } else { l.layout.as_str() };
    (plain(layout) && plain(&l.variant)).then(|| (layout.to_owned(), l.variant.clone()))
}

/// Preedit cursor offsets checked against the text: UTF-8 byte offsets on character boundaries with begin <= end.
/// Both -1 means no cursor. `None` for anything else.
pub fn preedit_cursor(text: &str, begin: i32, end: i32) -> Option<(i32, i32)> {
    if (begin, end) == (-1, -1) {
        return Some((-1, -1));
    }
    let on_boundary = |i: i32| usize::try_from(i).is_ok_and(|i| text.is_char_boundary(i));
    (on_boundary(begin) && on_boundary(end) && begin <= end).then_some((begin, end))
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

    fn layout(layout: &str, variant: &str) -> pb::KeyboardLayout {
        pb::KeyboardLayout { layout: layout.into(), variant: variant.into() }
    }

    #[test]
    fn empty_layout_means_us() {
        assert_eq!(xkb_names(&layout("", "")), Some(("us".into(), String::new())));
    }

    #[test]
    fn layout_and_variant_pass_through() {
        assert_eq!(xkb_names(&layout("ch", "fr")), Some(("ch".into(), "fr".into())));
        assert_eq!(xkb_names(&layout("us", "dvorak")), Some(("us".into(), "dvorak".into())));
    }

    #[test]
    fn non_xkb_names_are_refused() {
        assert_eq!(xkb_names(&layout("de;rm -rf", "")), None);
        assert_eq!(xkb_names(&layout("us", "a b")), None);
        assert_eq!(xkb_names(&layout(&"x".repeat(33), "")), None);
        assert_eq!(xkb_names(&layout("", "é")), None);
    }

    #[test]
    fn preedit_cursor_accepts_boundaries_only() {
        // "你" is three bytes in UTF-8.
        assert_eq!(preedit_cursor("你好", 0, 3), Some((0, 3)));
        assert_eq!(preedit_cursor("你好", 3, 6), Some((3, 6)));
        assert_eq!(preedit_cursor("你好", 1, 3), None);
        assert_eq!(preedit_cursor("ab", 0, 3), None);
        assert_eq!(preedit_cursor("ab", 2, 1), None);
        assert_eq!(preedit_cursor("ab", -1, -1), Some((-1, -1)));
        assert_eq!(preedit_cursor("ab", -1, 1), None);
    }
}
