// SPDX-License-Identifier: AGPL-3.0-or-later
//! `org.freedesktop.impl.portal.Settings`: appearance for `org.freedesktop.appearance`.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use zbus::{OwnedVariant, Variant, fdo, interface};

pub const INTERFACE: &str = "org.freedesktop.impl.portal.Settings";
pub const NAMESPACE: &str = "org.freedesktop.appearance";
pub const KEY_COLOR_SCHEME: &str = "color-scheme";
pub const KEY_ACCENT_COLOR: &str = "accent-color";
pub const KEY_CONTRAST: &str = "contrast";

/// Host appearance as reported to apps.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Appearance {
    pub dark_mode: bool,
    /// 0xRRGGBB; 0 means the host default (no accent).
    pub accent_rgb: u32,
}

/// `color-scheme`: 1 prefers dark, 2 prefers light.
pub fn color_scheme(a: Appearance) -> u32 {
    if a.dark_mode { 1 } else { 2 }
}

/// `accent-color` as RGB in 0..1, or None when the host has no accent (0).
pub fn accent_rgb(rgb: u32) -> Option<(f64, f64, f64)> {
    if rgb == 0 {
        return None;
    }
    let channel = |shift: u32| f64::from((rgb >> shift) & 0xff) / 255.0;
    Some((channel(16), channel(8), channel(0)))
}

/// The value of one key, or None when the key is unset.
pub fn value(a: Appearance, key: &str) -> Option<Variant<'static>> {
    match key {
        KEY_COLOR_SCHEME => Some(Variant::from(color_scheme(a))),
        KEY_ACCENT_COLOR => accent_rgb(a.accent_rgb).map(|(r, g, b)| Variant::new((r, g, b))),
        KEY_CONTRAST => Some(Variant::from(0u32)),
        _ => None,
    }
}

/// Keys whose value differs between `old` and `new`, with their new values.
pub fn changed(old: Appearance, new: Appearance) -> Vec<(&'static str, Variant<'static>)> {
    [KEY_COLOR_SCHEME, KEY_ACCENT_COLOR, KEY_CONTRAST]
        .into_iter()
        .filter(|key| value(old, key) != value(new, key))
        .filter_map(|key| value(new, key).map(|v| (key, v)))
        .collect()
}

/// Every key in the namespaces asked for. An empty list, `*`, or a dotted prefix (`org.`) matches.
fn wants(namespaces: &[String], ns: &str) -> bool {
    namespaces.is_empty()
        || namespaces.iter().any(|want| want == "*" || want == ns || (want.ends_with('.') && ns.starts_with(want.as_str())))
}

pub struct Settings {
    pub appearance: Arc<Mutex<Appearance>>,
}

impl Settings {
    fn current(&self) -> Appearance {
        *self.appearance.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[interface(name = "org.freedesktop.impl.portal.Settings")]
impl Settings {
    #[zbus(name = "ReadAll")]
    fn read_all(&self, namespaces: Vec<String>) -> HashMap<String, HashMap<String, OwnedVariant>> {
        let a = self.current();
        let mut out = HashMap::new();
        if wants(&namespaces, NAMESPACE) {
            let mut keys = HashMap::new();
            for key in [KEY_COLOR_SCHEME, KEY_ACCENT_COLOR, KEY_CONTRAST] {
                if let Some(v) = value(a, key).and_then(|v| OwnedVariant::try_from(v).ok()) {
                    keys.insert(key.to_owned(), v);
                }
            }
            out.insert(NAMESPACE.to_owned(), keys);
        }
        out
    }

    #[zbus(name = "Read")]
    fn read(&self, namespace: &str, key: &str) -> fdo::Result<OwnedVariant> {
        if namespace != NAMESPACE {
            return Err(fdo::Error::Failed(format!("unknown setting {namespace}.{key}")));
        }
        value(self.current(), key)
            .and_then(|v| OwnedVariant::try_from(v).ok())
            .ok_or_else(|| fdo::Error::Failed(format!("unknown setting {namespace}.{key}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn color_scheme_maps_dark_and_light() {
        assert_eq!(color_scheme(Appearance { dark_mode: true, accent_rgb: 0 }), 1);
        assert_eq!(color_scheme(Appearance { dark_mode: false, accent_rgb: 0 }), 2);
    }

    #[test]
    fn accent_converts_rgb_to_unit_floats() {
        assert_eq!(accent_rgb(0), None);
        assert_eq!(accent_rgb(0xff0000), Some((1.0, 0.0, 0.0)));
        assert_eq!(accent_rgb(0x00ff80), Some((0.0, 1.0, 128.0 / 255.0)));
    }

    #[test]
    fn unset_accent_has_no_value() {
        assert!(value(Appearance::default(), KEY_ACCENT_COLOR).is_none());
        assert!(value(Appearance { dark_mode: false, accent_rgb: 1 }, KEY_ACCENT_COLOR).is_some());
        assert!(value(Appearance::default(), "unknown").is_none());
    }

    #[test]
    fn changed_lists_only_differing_keys() {
        let light = Appearance { dark_mode: false, accent_rgb: 0x112233 };
        let dark = Appearance { dark_mode: true, accent_rgb: 0x112233 };
        let keys: Vec<&str> = changed(light, dark).iter().map(|(k, _)| *k).collect();
        assert_eq!(keys, vec![KEY_COLOR_SCHEME]);
        let accent = Appearance { dark_mode: true, accent_rgb: 0x445566 };
        let keys: Vec<&str> = changed(dark, accent).iter().map(|(k, _)| *k).collect();
        assert_eq!(keys, vec![KEY_ACCENT_COLOR]);
    }

    #[test]
    fn namespace_filter() {
        assert!(wants(&[], NAMESPACE));
        assert!(wants(&["*".into()], NAMESPACE));
        assert!(wants(&["org.freedesktop.".into()], NAMESPACE));
        assert!(wants(&[NAMESPACE.into()], NAMESPACE));
        assert!(!wants(&["org.gnome.desktop".into()], NAMESPACE));
    }
}
