// SPDX-License-Identifier: AGPL-3.0-or-later
//! `zwp_text_input_v3` for guest apps. The compositor is the input method: the host's IME results arrive as
//! `ToGuest.text_input` and are sent to the focused client's active text input. This module replaces smithay's text
//! input global because that one keeps the caret rectangle to itself; the host needs it to place the candidate
//! window (`TextInputCursor`), and the content purpose to leave passwords alone (`TextInputState.secure`).

use smithay::{
    reexports::{
        wayland_protocols::wp::text_input::zv3::server::{
            zwp_text_input_manager_v3::{self, ZwpTextInputManagerV3},
            zwp_text_input_v3::{self, ContentPurpose, ZwpTextInputV3},
        },
        wayland_server::{
            Client, DataInit, DisplayHandle, New, Resource,
            backend::{ClientId, ObjectId},
            protocol::wl_surface::WlSurface,
        },
    },
    wayland::{Dispatch2, GlobalDispatch2},
};

use crate::{pb, render::geometry, state::State};

/// Largest caret rectangle side the host will place a window by; anything bigger is a hostile or broken client.
const MAX_RECT_SIDE: i32 = 16_384;

/// Data of the `zwp_text_input_manager_v3` global.
pub struct TextInputGlobal;
/// Data of each `zwp_text_input_v3` object. The state lives in `TextInputs`, keyed by the object.
pub struct TextInputData;

/// Double-buffered requests of one text input, applied by `commit`.
#[derive(Default)]
struct Pending {
    enable: Option<bool>,
    purpose: Option<ContentPurpose>,
    cursor: Option<(i32, i32, i32, i32)>,
}

struct Instance {
    object: ZwpTextInputV3,
    /// Commits received so far; `done` echoes it.
    serial: u32,
    purpose: ContentPurpose,
    pending: Pending,
}

/// All text inputs of the seat: who has keyboard focus and which input is enabled.
#[derive(Default)]
pub struct TextInputs {
    instances: Vec<Instance>,
    focus: Option<WlSurface>,
    active: Option<ObjectId>,
}

impl GlobalDispatch2<ZwpTextInputManagerV3, State> for TextInputGlobal {
    fn bind(
        &self,
        _: &mut State,
        _: &DisplayHandle,
        _: &Client,
        resource: New<ZwpTextInputManagerV3>,
        data_init: &mut DataInit<'_, State>,
    ) {
        data_init.init(resource, TextInputGlobal);
    }
}

impl Dispatch2<ZwpTextInputManagerV3, State> for TextInputGlobal {
    fn request(
        &self,
        state: &mut State,
        _: &Client,
        _: &ZwpTextInputManagerV3,
        request: zwp_text_input_manager_v3::Request,
        _: &DisplayHandle,
        data_init: &mut DataInit<'_, State>,
    ) {
        if let zwp_text_input_manager_v3::Request::GetTextInput { id, .. } = request {
            let object = data_init.init(id, TextInputData);
            let inputs = &mut state.text_inputs;
            if let Some(focus) = inputs.focus.as_ref().filter(|f| same_client(&object, f)) {
                object.enter(focus);
            }
            inputs.instances.push(Instance { object, serial: 0, purpose: ContentPurpose::Normal, pending: Pending::default() });
        }
    }
}

impl Dispatch2<ZwpTextInputV3, State> for TextInputData {
    fn request(
        &self,
        state: &mut State,
        _: &Client,
        resource: &ZwpTextInputV3,
        request: zwp_text_input_v3::Request,
        _: &DisplayHandle,
        _: &mut DataInit<'_, State>,
    ) {
        let Some(instance) = state.text_inputs.instances.iter_mut().find(|i| i.object == *resource) else { return };
        match request {
            zwp_text_input_v3::Request::Enable => instance.pending.enable = Some(true),
            zwp_text_input_v3::Request::Disable => instance.pending.enable = Some(false),
            zwp_text_input_v3::Request::SetContentType { purpose, .. } => {
                instance.pending.purpose = Some(purpose.into_result().unwrap_or(ContentPurpose::Normal));
            }
            zwp_text_input_v3::Request::SetCursorRectangle { x, y, width, height } => {
                instance.pending.cursor = Some((x, y, width, height));
            }
            zwp_text_input_v3::Request::Commit => {
                instance.serial = instance.serial.wrapping_add(1);
                let pending = std::mem::take(&mut instance.pending);
                if let Some(purpose) = pending.purpose {
                    instance.purpose = purpose;
                }
                let purpose = instance.purpose;
                state.text_input_commit(resource, pending, purpose);
            }
            _ => {}
        }
    }

    fn destroyed(&self, state: &mut State, _: ClientId, resource: &ZwpTextInputV3) {
        let id = resource.id();
        state.text_inputs.instances.retain(|i| i.object.id() != id);
        if state.text_inputs.active.as_ref() == Some(&id) {
            state.text_inputs.active = None;
            if let Some(focus) = state.text_inputs.focus.clone() {
                state.send_text_input(&focus, false, false);
            }
        }
    }
}

fn same_client(object: &ZwpTextInputV3, surface: &WlSurface) -> bool {
    object.id().same_client_as(&surface.id())
}

fn is_secure(purpose: ContentPurpose) -> bool {
    matches!(purpose, ContentPurpose::Password | ContentPurpose::Pin)
}

impl State {
    /// Keyboard focus moved: the old client's text inputs leave, the new client's enter. Whatever was enabled ends,
    /// and the host is told.
    pub fn text_input_focus(&mut self, surface: Option<WlSurface>) {
        let inputs = &mut self.text_inputs;
        let Some(old) = inputs.focus.take() else {
            return self.text_input_enter(surface);
        };
        for instance in inputs.instances.iter().filter(|i| same_client(&i.object, &old)) {
            instance.object.leave(&old);
        }
        let was_active = inputs.active.take().is_some();
        if was_active {
            self.send_text_input(&old, false, false);
        }
        self.text_input_enter(surface);
    }

    fn text_input_enter(&mut self, surface: Option<WlSurface>) {
        let Some(surface) = surface else { return };
        for instance in self.text_inputs.instances.iter().filter(|i| same_client(&i.object, &surface)) {
            instance.object.enter(&surface);
        }
        self.text_inputs.focus = Some(surface);
    }

    /// Applies one `commit`: enable and disable, the content purpose, and the caret rectangle. Only the focused
    /// client counts, and only one of its text inputs can be enabled at a time.
    fn text_input_commit(&mut self, object: &ZwpTextInputV3, pending: Pending, purpose: ContentPurpose) {
        let Some(focus) = self.text_inputs.focus.clone().filter(|f| same_client(object, f)) else { return };
        let id = object.id();
        let active = self.text_inputs.active.clone();
        if active.as_ref().is_some_and(|a| *a != id) {
            return;
        }
        match pending.enable {
            Some(true) => {
                self.text_inputs.active = Some(id);
                self.send_text_input(&focus, true, is_secure(purpose));
            }
            Some(false) => {
                if active.is_some() {
                    self.text_inputs.active = None;
                    self.send_text_input(&focus, false, false);
                }
                return;
            }
            None if active.is_none() => return,
            None if pending.purpose.is_some() => self.send_text_input(&focus, true, is_secure(purpose)),
            None => {}
        }
        if let Some(rect) = pending.cursor {
            self.send_text_cursor(&focus, rect);
        }
    }

    /// The caret rectangle in the window's own coordinates (the host shows the surface's geometry, not its origin).
    fn send_text_cursor(&mut self, surface: &WlSurface, (x, y, width, height): (i32, i32, i32, i32)) {
        let sane = (0..=MAX_RECT_SIDE).contains(&width) && (0..=MAX_RECT_SIDE).contains(&height);
        let Some(window) = self.win_by_surface(surface).map(|w| w.id).filter(|_| sane) else { return };
        let geo = geometry(surface);
        let cursor = pb::TextInputCursor {
            window,
            x: x.saturating_sub(geo.loc.x),
            y: y.saturating_sub(geo.loc.y),
            width: width as u32,
            height: height as u32,
        };
        tracing::debug!(window, x = cursor.x, y = cursor.y, width, height, "caret");
        self.send(pb::to_host::Msg::TextInputCursor(cursor));
    }

    /// Applies the host's composition result to the enabled text input of the focused client. Dropped unless `window`
    /// is the focused window, so a late update cannot land in another client.
    pub fn text_input_update(&mut self, t: pb::TextInput) {
        let Some(focus) = self.text_inputs.focus.clone() else { return };
        if self.win_by_surface(&focus).map(|w| w.id) != Some(t.window) {
            tracing::debug!("text input for window {} dropped: not focused", t.window);
            return;
        }
        let Some(active) = self.text_inputs.active.clone() else { return };
        let Some(instance) = self.text_inputs.instances.iter().find(|i| i.object.id() == active) else { return };
        let object = &instance.object;
        if let Some(d) = &t.delete_surrounding {
            object.delete_surrounding_text(d.before, d.after);
        }
        if let Some(c) = &t.commit {
            object.commit_string((!c.text.is_empty()).then(|| c.text.clone()));
        }
        if let Some(p) = &t.preedit {
            let text = (!p.text.is_empty()).then(|| p.text.clone());
            let (begin, end) = crate::host::preedit_cursor(&p.text, p.cursor_begin, p.cursor_end)
                .unwrap_or((p.text.len() as i32, p.text.len() as i32));
            object.preedit_string(text, begin, end);
        }
        object.done(instance.serial);
    }
}
