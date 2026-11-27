// SPDX-License-Identifier: AGPL-3.0-or-later
//! Finds the process behind an X11 window.
//!
//! X11 apps reach the compositor through `xwayland-satellite`, so every X11 window belongs to the same Wayland client
//! and the client's process says nothing about the app. The X server knows better: with the X-Resource extension it
//! reports the process that opened each client connection. The caller then walks that process's ancestors to the
//! `flatpak run` it started, exactly as for a native Wayland client.

use x11rb::{
    connection::Connection,
    protocol::{
        res::{ClientIdMask, ClientIdSpec, ConnectionExt as _},
        xproto::{Atom, AtomEnum, ConnectionExt as _, Window},
    },
    rust_connection::RustConnection,
};

/// How deep to look below the root for windows that carry a `WM_CLASS`. Rootless Xwayland puts client windows
/// directly under the root; a window manager's frames would add one level.
const SEARCH_DEPTH: u32 = 2;

/// The process that owns the X11 window whose class (or instance) name is `app_id` and whose title is `title`.
/// An empty `title` matches any. `None` when there is no such window or the X server cannot say.
pub fn owner_pid(app_id: &str, title: &str) -> Option<i32> {
    let (conn, screen) = RustConnection::connect(Some(crate::satellite::DISPLAY)).ok()?;
    let root = conn.setup().roots.get(screen)?.root;
    let net_wm_name = intern(&conn, b"_NET_WM_NAME")?;
    let utf8 = intern(&conn, b"UTF8_STRING")?;
    let window = find_window(&conn, root, SEARCH_DEPTH, &|w| {
        let class = property(&conn, w, AtomEnum::WM_CLASS.into(), AtomEnum::STRING.into()).unwrap_or_default();
        if !class_matches(&class, app_id) {
            return false;
        }
        let name = property(&conn, w, net_wm_name, utf8)
            .or_else(|| property(&conn, w, AtomEnum::WM_NAME.into(), AtomEnum::STRING.into()))
            .unwrap_or_default();
        title.is_empty() || name == title.as_bytes()
    })?;
    let spec = ClientIdSpec { client: window, mask: ClientIdMask::LOCAL_CLIENT_PID };
    let ids = conn.res_query_client_ids(&[spec]).ok()?.reply().ok()?.ids;
    ids.first()?.value.first().and_then(|&pid| i32::try_from(pid).ok())
}

/// Whether a `WM_CLASS` value (two NUL-terminated strings: instance, then class) names `app_id`, either way.
fn class_matches(wm_class: &[u8], app_id: &str) -> bool {
    !app_id.is_empty()
        && wm_class.split(|&b| b == 0).filter(|part| !part.is_empty()).any(|part| part == app_id.as_bytes())
}

fn intern(conn: &RustConnection, name: &[u8]) -> Option<Atom> {
    Some(conn.intern_atom(false, name).ok()?.reply().ok()?.atom)
}

fn property(conn: &RustConnection, window: Window, property: Atom, kind: Atom) -> Option<Vec<u8>> {
    let reply = conn.get_property(false, window, property, kind, 0, 1024).ok()?.reply().ok()?;
    (!reply.value.is_empty()).then_some(reply.value)
}

/// Depth-first search of the window tree below `window` for the first window satisfying `accept`.
fn find_window(conn: &RustConnection, window: Window, depth: u32, accept: &dyn Fn(Window) -> bool) -> Option<Window> {
    let children = conn.query_tree(window).ok()?.reply().ok()?.children;
    for child in children {
        if accept(child) {
            return Some(child);
        }
        if depth > 1
            && let Some(found) = find_window(conn, child, depth - 1, accept)
        {
            return Some(found);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::class_matches;

    #[test]
    fn class_matches_the_instance_or_the_class_name() {
        let wm_class = b"gimp-2.10\0Gimp-2.10\0";
        assert!(class_matches(wm_class, "gimp-2.10"));
        assert!(class_matches(wm_class, "Gimp-2.10"));
        assert!(!class_matches(wm_class, "gimp"));
    }

    #[test]
    fn class_matching_needs_a_whole_name_and_a_non_empty_app_id() {
        assert!(!class_matches(b"vlc\0vlc\0", ""));
        assert!(!class_matches(b"", "vlc"));
        assert!(!class_matches(b"vlcx\0VLC\0", "vlc"));
    }
}
