// SPDX-License-Identifier: AGPL-3.0-or-later
//! D-Bus portal backends served by crosswindd on the session bus.
//!
//! zbus runs on its own executor thread. A method that needs the macOS host sends a `CallRequest`
//! over a calloop channel; the loop thread issues `Control::call` and hands back the reply
//! receiver. The caller then waits for the reply off the zbus executor, with a timeout.

pub mod filechooser;
pub mod notification;
pub mod open_url;
pub mod settings;

use std::{
    process::{Command, Stdio},
    sync::{Arc, Mutex, mpsc},
    thread,
    time::{Duration, Instant},
};

use smithay::reexports::calloop::channel;
use zbus::{Connection, connection::Builder};

use crate::control_pb::{self as pb, call};

pub const BUS_NAME: &str = "org.freedesktop.impl.portal.desktop.crosswind";
pub const OBJECT_PATH: &str = "/org/freedesktop/portal/desktop";
/// How long a guest-initiated call waits for the host's reply.
pub const CALL_TIMEOUT: Duration = Duration::from_secs(30);

/// A host call asked for by a backend thread. The loop thread answers `reply` with the receiver
/// that `Control::call` returned; the reply itself arrives on that receiver.
pub struct CallRequest {
    pub app_id: String,
    pub body: call::Body,
    pub reply: mpsc::Sender<mpsc::Receiver<pb::CallReply>>,
}

/// Thread-safe handle to the loop thread's `Control::call`.
#[derive(Clone)]
pub struct Bridge {
    calls: channel::Sender<CallRequest>,
}

impl Bridge {
    pub fn new(calls: channel::Sender<CallRequest>) -> Self {
        Self { calls }
    }

    /// Sends a call to the host and waits for its reply. Blocks; never call it on the loop thread.
    pub fn call_blocking(&self, app_id: &str, body: call::Body) -> Result<pb::CallReply, String> {
        self.call_blocking_for(app_id, body, CALL_TIMEOUT)
    }

    /// Like `call_blocking`, with a custom reply timeout (a file chooser waits for the user).
    pub fn call_blocking_for(
        &self,
        app_id: &str,
        body: call::Body,
        timeout: Duration,
    ) -> Result<pb::CallReply, String> {
        let deadline = Instant::now() + timeout;
        let (tx, rx) = mpsc::channel();
        self.calls
            .send(CallRequest { app_id: app_id.to_owned(), body, reply: tx })
            .map_err(|_| "crosswindd loop is gone".to_owned())?;
        let waiting = rx.recv_timeout(CALL_TIMEOUT).map_err(|e| format!("host call not started: {e}"))?;
        waiting
            .recv_timeout(deadline.saturating_duration_since(Instant::now()))
            .map_err(|e| format!("no reply from host: {e}"))
    }

    /// Sends a call without waiting for the host's reply (the reply is discarded).
    pub fn post(&self, app_id: &str, body: call::Body) {
        let (tx, _rx) = mpsc::channel();
        if self.calls.send(CallRequest { app_id: app_id.to_owned(), body, reply: tx }).is_err() {
            tracing::warn!("portal call dropped: loop is gone");
        }
    }
}

/// Running backend: the session-bus connection that serves the interfaces, plus the appearance
/// they report. Cloning shares the same connection and state.
#[derive(Clone)]
pub struct Portal {
    appearance: Arc<Mutex<settings::Appearance>>,
    conn: Connection,
}

impl Portal {
    /// Connects to `address`, requests `BUS_NAME` and serves the Settings, Notification and
    /// FileChooser interfaces at `OBJECT_PATH`.
    pub fn start(address: &str, bridge: Bridge, appearance: settings::Appearance) -> zbus::Result<Self> {
        let shared = Arc::new(Mutex::new(appearance));
        let conn = zbus::block_on(async {
            Builder::address(address)
                .name(BUS_NAME)
                .serve_at(OBJECT_PATH, settings::Settings { appearance: shared.clone() })
                .serve_at(OBJECT_PATH, notification::Notifications { bridge: bridge.clone() })
                .serve_at(OBJECT_PATH, filechooser::FileChooser { bridge })
                .build()
                .await
        })?;
        Ok(Self { appearance: shared, conn })
    }

    /// Stores new appearance values and emits `SettingChanged` for every key that changed.
    /// Runs on the loop thread; the emit is a local bus write.
    pub fn set_appearance(&self, next: settings::Appearance) {
        let changed = {
            let mut cur = self.appearance.lock().unwrap_or_else(|e| e.into_inner());
            let changed = settings::changed(*cur, next);
            *cur = next;
            changed
        };
        for (key, value) in changed {
            let body = (settings::NAMESPACE, key, value);
            let sent = zbus::block_on(self.conn.emit_signal(
                None::<&str>,
                OBJECT_PATH,
                settings::INTERFACE,
                "SettingChanged",
                &body,
            ));
            if let Err(e) = sent {
                tracing::warn!(key, "SettingChanged not emitted: {e}");
            }
        }
    }
}

/// Starts the xdg-desktop-portal frontend on the same bus. It routes `org.freedesktop.portal.*`
/// calls to our backend (see `crosswind-portals.conf`). Its exit is only logged.
pub fn spawn_frontend(address: &str) {
    let child = Command::new("xdg-desktop-portal")
        .env("DBUS_SESSION_BUS_ADDRESS", address)
        .env("XDG_CURRENT_DESKTOP", "crosswind")
        .stdin(Stdio::null())
        .spawn();
    match child {
        Ok(mut child) => {
            thread::spawn(move || match child.wait() {
                Ok(status) => tracing::warn!(?status, "xdg-desktop-portal exited"),
                Err(e) => tracing::warn!("xdg-desktop-portal wait: {e}"),
            });
        }
        Err(e) => tracing::warn!("xdg-desktop-portal not started: {e}"),
    }
}

#[cfg(test)]
mod integration {
    //! Serves the backends on a private session bus and calls them with a zbus client.
    //! Needs `dbus-daemon`; run in the Lima VM with `cargo test --release -- --ignored --nocapture`.
    use std::{collections::HashMap, process::Command, sync::mpsc, thread, time::Duration};

    use smithay::reexports::calloop::{EventLoop, channel};
    use zbus::{OwnedVariant, Variant};

    use super::*;
    use crate::control_pb::{call_reply, call::Body};

    fn private_bus() -> String {
        let out = Command::new("dbus-daemon").args(["--session", "--fork", "--print-address"]).output().expect("dbus-daemon");
        assert!(out.status.success(), "dbus-daemon failed");
        String::from_utf8_lossy(&out.stdout).trim().to_owned()
    }

    /// A stand-in for the loop thread: answers every host call with `Ok` and reports the body.
    fn fake_host() -> (Bridge, mpsc::Receiver<Body>) {
        let (calls_tx, calls_rx) = channel::channel::<CallRequest>();
        let (seen_tx, seen_rx) = mpsc::channel();
        thread::spawn(move || {
            let mut event_loop: EventLoop<()> = EventLoop::try_new().expect("event loop");
            event_loop
                .handle()
                .insert_source(calls_rx, move |event, _, _| {
                    if let channel::Event::Msg(req) = event {
                        let (reply_tx, reply_rx) = mpsc::channel();
                        let _ = reply_tx.send(pb::CallReply { id: 1, result: Some(call_reply::Result::Ok(pb::Ok {})) });
                        let _ = req.reply.send(reply_rx);
                        let _ = seen_tx.send(req.body);
                    }
                })
                .expect("calls source");
            event_loop.run(None, &mut (), |_| {}).expect("loop");
        });
        (Bridge::new(calls_tx), seen_rx)
    }

    #[test]
    #[ignore = "needs dbus-daemon; run in the Lima VM"]
    fn backends_answer_on_a_private_bus() {
        let address = private_bus();
        let (bridge, seen) = fake_host();
        let appearance = settings::Appearance { dark_mode: true, accent_rgb: 0x3366ff };
        let portal = Portal::start(&address, bridge, appearance).expect("start backends");
        let client = zbus::block_on(Builder::address(address.as_str()).build()).expect("client");

        let read = |ns: &str, key: &str| -> OwnedVariant {
            zbus::block_on(client.call_method(Some(BUS_NAME), OBJECT_PATH, Some(settings::INTERFACE), "Read", &(ns, key)))
                .expect("Read")
                .body()
                .deserialize()
                .expect("variant reply")
        };
        let scheme = u32::try_from(read(settings::NAMESPACE, settings::KEY_COLOR_SCHEME)).expect("u32");
        assert_eq!(scheme, 1, "dark mode reports color-scheme 1");
        let accent = <(f64, f64, f64)>::try_from(read(settings::NAMESPACE, settings::KEY_ACCENT_COLOR)).expect("(ddd)");
        assert!((accent.0 - 0.2).abs() < 0.01 && (accent.1 - 0.4).abs() < 0.01 && (accent.2 - 1.0).abs() < 0.01);
        let contrast = u32::try_from(read(settings::NAMESPACE, settings::KEY_CONTRAST)).expect("u32");
        assert_eq!(contrast, 0);
        println!("Read color-scheme={scheme} accent={accent:?} contrast={contrast}");

        let all: HashMap<String, HashMap<String, OwnedVariant>> = zbus::block_on(client.call_method(
            Some(BUS_NAME),
            OBJECT_PATH,
            Some(settings::INTERFACE),
            "ReadAll",
            &(vec![settings::NAMESPACE],),
        ))
        .expect("ReadAll")
        .body()
        .deserialize()
        .expect("a{sa{sv}}");
        let keys = &all[settings::NAMESPACE];
        assert_eq!(keys.len(), 3, "color-scheme, accent-color and contrast");
        println!("ReadAll keys: {:?}", keys.keys().collect::<Vec<_>>());

        // Unset accent: the key is omitted.
        portal.set_appearance(settings::Appearance { dark_mode: true, accent_rgb: 0 });
        let all: HashMap<String, HashMap<String, OwnedVariant>> = zbus::block_on(client.call_method(
            Some(BUS_NAME),
            OBJECT_PATH,
            Some(settings::INTERFACE),
            "ReadAll",
            &(Vec::<String>::new(),),
        ))
        .expect("ReadAll")
        .body()
        .deserialize()
        .expect("a{sa{sv}}");
        assert!(!all[settings::NAMESPACE].contains_key(settings::KEY_ACCENT_COLOR));

        // Notification: the dict reaches the host as Notify with the PNG icon.
        let icon = Variant::new(("bytes", Variant::from(vec![0x89u8, b'P', b'N', b'G'])));
        let mut dict: HashMap<&str, Variant> = HashMap::new();
        dict.insert("title", Variant::from("Build done"));
        dict.insert("body", Variant::from("42 tests passed"));
        dict.insert("icon", icon);
        zbus::block_on(client.call_method(
            Some(BUS_NAME),
            OBJECT_PATH,
            Some("org.freedesktop.impl.portal.Notification"),
            "AddNotification",
            &("org.example.App", "n1", dict),
        ))
        .expect("AddNotification");
        match seen.recv_timeout(Duration::from_secs(5)).expect("host call") {
            Body::Notify(n) => {
                assert_eq!(n.notification_id, "n1");
                assert_eq!(n.title, "Build done");
                assert_eq!(n.icon_png, vec![0x89, b'P', b'N', b'G']);
                assert!(!n.withdraw);
            }
            other => panic!("unexpected host call: {other:?}"),
        }
    }
}
