// SPDX-License-Identifier: AGPL-3.0-or-later
//! `org.freedesktop.impl.portal.Notification`: forwards notifications to the host as `Call::Notify`.
//! `ActionInvoked` is not emitted yet (the host has no reply path for it).

use std::collections::HashMap;

use zbus::{OwnedVariant, Variant, interface};

use super::Bridge;
use crate::control_pb::{self as pb, call};
use crate::limits;

/// The parts of an `a{sv}` notification dict that the host understands.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Parsed {
    pub title: String,
    pub body: String,
    /// PNG bytes from an `icon` of `(sv)` form `("bytes", ay)`; empty for themed or fd icons.
    pub icon_png: Vec<u8>,
    pub default_action: String,
}

/// Parses the dict, cutting every field to its limit: the host shows these on the Mac.
pub fn parse(dict: &HashMap<String, OwnedVariant>) -> Parsed {
    Parsed {
        title: limits::clean(&string(dict, "title"), limits::MAX_NOTIFY_TITLE),
        body: limits::clean(&string(dict, "body"), limits::MAX_NOTIFY_BODY),
        icon_png: icon_bytes(dict),
        default_action: limits::clean(&string(dict, "default-action"), limits::MAX_FIELD),
    }
}

fn string(dict: &HashMap<String, OwnedVariant>, key: &str) -> String {
    dict.get(key).and_then(|v| String::try_from(v.clone()).ok()).unwrap_or_default()
}

fn icon_bytes(dict: &HashMap<String, OwnedVariant>) -> Vec<u8> {
    let Some(icon) = dict.get("icon") else {
        return Vec::new();
    };
    let Ok((kind, inner)) = <(String, OwnedVariant)>::try_from(icon.clone()) else {
        return Vec::new();
    };
    if kind != "bytes" {
        return Vec::new();
    }
    // Peel nested variants: the payload may arrive wrapped in one or more `v` layers.
    let mut payload: Variant = inner.into();
    while let Variant::Variant(v) = payload {
        payload = *v;
    }
    let bytes = Vec::<u8>::try_from(payload).unwrap_or_default();
    if bytes.len() > limits::MAX_NOTIFY_ICON { Vec::new() } else { bytes }
}

pub struct Notifications {
    pub bridge: Bridge,
}

#[interface(name = "org.freedesktop.impl.portal.Notification")]
impl Notifications {
    #[zbus(name = "AddNotification")]
    fn add_notification(&self, app_id: &str, id: &str, notification: HashMap<String, OwnedVariant>) {
        let n = parse(&notification);
        let body = call::Body::Notify(pb::Notify {
            notification_id: limits::clean(id, limits::MAX_IDENTIFIER),
            title: n.title,
            body: n.body,
            icon_png: n.icon_png,
            default_action: n.default_action,
            replace: true,
            withdraw: false,
        });
        self.bridge.post(app_id, body);
    }

    #[zbus(name = "RemoveNotification")]
    fn remove_notification(&self, app_id: &str, id: &str) {
        let body = call::Body::Notify(pb::Notify {
            notification_id: limits::clean(id, limits::MAX_IDENTIFIER),
            withdraw: true,
            ..Default::default()
        });
        self.bridge.post(app_id, body);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::Variant;

    fn owned(v: Variant<'_>) -> OwnedVariant {
        OwnedVariant::try_from(v).expect("owned value")
    }

    #[test]
    fn parses_text_fields_and_default_action() {
        let mut dict = HashMap::new();
        dict.insert("title".to_owned(), owned(Variant::from("Build done")));
        dict.insert("body".to_owned(), owned(Variant::from("42 tests passed")));
        dict.insert("default-action".to_owned(), owned(Variant::from("open")));
        let n = parse(&dict);
        assert_eq!(n.title, "Build done");
        assert_eq!(n.body, "42 tests passed");
        assert_eq!(n.default_action, "open");
        assert!(n.icon_png.is_empty());
    }

    #[test]
    fn bytes_icon_is_passed_through() {
        let mut dict = HashMap::new();
        let icon = Variant::new(("bytes", Variant::from(vec![0x89u8, b'P', b'N', b'G'])));
        dict.insert("icon".to_owned(), owned(icon));
        assert_eq!(parse(&dict).icon_png, vec![0x89, b'P', b'N', b'G']);
    }

    #[test]
    fn themed_icon_is_dropped() {
        let mut dict = HashMap::new();
        let icon = Variant::new(("themed", Variant::from(vec!["dialog-information"])));
        dict.insert("icon".to_owned(), owned(icon));
        assert!(parse(&dict).icon_png.is_empty());
    }

    #[test]
    fn missing_or_mistyped_fields_are_empty() {
        let mut dict = HashMap::new();
        dict.insert("title".to_owned(), owned(Variant::from(7u32)));
        dict.insert("icon".to_owned(), owned(Variant::from("not a struct")));
        assert_eq!(parse(&dict), Parsed::default());
    }
}
