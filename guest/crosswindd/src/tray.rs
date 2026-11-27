// SPDX-License-Identifier: AGPL-3.0-or-later
//! Tray icons. Serves `org.kde.StatusNotifierWatcher` on the session bus so apps register their
//! `StatusNotifierItem`; each item is mirrored to the host (a menu bar icon on the Mac) and clicks come back as
//! `Activate`, `SecondaryActivate` or `ContextMenu` calls on the item.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, MutexGuard},
    thread,
};

use futures_util::{StreamExt, stream};
use smithay::reexports::calloop::channel;
use zbus::{Connection, connection::Builder, fdo, interface, message::Header, object_server::SignalEmitter};

use crate::{
    control::Note,
    control_pb::{self as pb, event, tray_activate::Kind},
    limits,
};

const WATCHER_NAME: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const ITEM_INTERFACE: &str = "org.kde.StatusNotifierItem";
/// Where an item lives when the app registers a bare bus name.
const DEFAULT_ITEM_PATH: &str = "/StatusNotifierItem";

/// Where one item lives on the bus.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Address {
    bus_name: String,
    path: String,
}

impl Address {
    /// The id the host knows the item by.
    fn id(&self) -> String {
        format!("{}{}", self.bus_name, self.path)
    }

    /// Parses what an app passes to `RegisterStatusNotifierItem`: a bus name, or an object path on the caller's own
    /// connection (`sender`).
    fn parse(service: &str, sender: &str) -> Option<Self> {
        let address = if service.starts_with('/') {
            Self { bus_name: sender.to_owned(), path: service.to_owned() }
        } else {
            Self { bus_name: service.to_owned(), path: DEFAULT_ITEM_PATH.to_owned() }
        };
        (!address.bus_name.is_empty() && address.id().len() <= limits::MAX_TRAY_ID).then_some(address)
    }
}

type Items = Arc<Mutex<HashMap<String, Address>>>;

fn lock(items: &Items) -> MutexGuard<'_, HashMap<String, Address>> {
    items.lock().unwrap_or_else(|e| e.into_inner())
}

/// The running watcher. Cloning shares the connection and the registered items.
#[derive(Clone)]
pub struct Tray {
    conn: Connection,
    items: Items,
}

impl Tray {
    /// Connects to the session bus at `address` and takes the watcher name. `notes` carries events to the loop.
    pub fn start(address: &str, notes: channel::Sender<Note>) -> zbus::Result<Self> {
        let items: Items = Arc::default();
        let watcher = Watcher { items: items.clone(), notes };
        let conn = zbus::block_on(Builder::address(address).name(WATCHER_NAME).serve_at(WATCHER_PATH, watcher).build())?;
        Ok(Self { conn, items })
    }

    /// Forwards a click on the host's icon to the app.
    pub fn activate(&self, id: &str, kind: Kind, x: i32, y: i32) {
        let Some(address) = lock(&self.items).get(id).cloned() else { return };
        let method = match kind {
            Kind::Primary => "Activate",
            Kind::Secondary => "SecondaryActivate",
            Kind::ContextMenu => "ContextMenu",
        };
        let conn = self.conn.clone();
        thread::spawn(move || {
            let (bus_name, path) = (address.bus_name.as_str(), address.path.as_str());
            if let Err(e) = zbus::block_on(conn.call_method(Some(bus_name), path, Some(ITEM_INTERFACE), method, &(x, y))) {
                tracing::debug!(%method, "tray click not delivered: {e}");
            }
        });
    }
}

struct Watcher {
    items: Items,
    notes: channel::Sender<Note>,
}

#[interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &self,
        service: &str,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        let sender = header.sender().map(|s| s.to_string()).unwrap_or_default();
        let address = Address::parse(service, &sender).ok_or_else(|| fdo::Error::InvalidArgs("bad item".into()))?;
        let id = address.id();
        {
            let mut items = lock(&self.items);
            if items.contains_key(&id) {
                return Ok(());
            }
            if items.len() >= limits::MAX_TRAY_ITEMS {
                return Err(fdo::Error::LimitsExceeded("too many tray icons".into()));
            }
            items.insert(id.clone(), address.clone());
        }
        Self::status_notifier_item_registered(&emitter, &id).await?;
        let (conn, items, notes) = (emitter.connection().clone(), self.items.clone(), self.notes.clone());
        thread::spawn(move || zbus::block_on(watch(conn, items, notes, address)));
        Ok(())
    }

    fn register_status_notifier_host(&self, _service: &str) {}

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        lock(&self.items).keys().cloned().collect()
    }

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(emitter: &SignalEmitter<'_>, service: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(emitter: &SignalEmitter<'_>, service: &str) -> zbus::Result<()>;
}

/// What wakes the per-item task.
enum Wake {
    /// The item emitted a signal (new icon, title or status): read it again.
    Changed,
    /// The item's bus name changed owner; `true` when it has no owner any more.
    Owner(bool),
}

/// Mirrors one item to the host until its app goes away.
async fn watch(conn: Connection, items: Items, notes: channel::Sender<Note>, address: Address) {
    let id = address.id();
    if let Err(e) = mirror(&conn, &notes, &address, &id).await {
        tracing::debug!(%id, "tray item not mirrored: {e}");
    }
    lock(&items).remove(&id);
    let _ = notes.send(Note::Event(pb::Event {
        body: Some(event::Body::TrayItemRemoved(pb::TrayItemRemoved { id: id.clone() })),
    }));
    if let Ok(emitter) = SignalEmitter::new(&conn, WATCHER_PATH) {
        let _ = Watcher::status_notifier_item_unregistered(&emitter, &id).await;
    }
}

async fn mirror(conn: &Connection, notes: &channel::Sender<Note>, address: &Address, id: &str) -> zbus::Result<()> {
    let item = zbus::Proxy::new(conn, address.bus_name.as_str(), address.path.as_str(), ITEM_INTERFACE).await?;
    let dbus = fdo::DBusProxy::new(conn).await?;
    let name = zbus::names::BusName::try_from(address.bus_name.as_str())?;
    let signals = item.receive_all_signals().await?.map(|_| Wake::Changed);
    let owner = dbus
        .receive_name_owner_changed_with_args(&[(0, address.bus_name.as_str())])
        .await?
        .map(|change| Wake::Owner(change.args().is_ok_and(|a| a.new_owner().is_none())));
    let mut wakes = stream::select(signals, owner);
    loop {
        if !dbus.name_has_owner(name.clone()).await? {
            return Ok(());
        }
        let changed = snapshot(&item, id).await?;
        let _ = notes.send(Note::Event(pb::Event { body: Some(event::Body::TrayItemChanged(changed)) }));
        loop {
            match wakes.next().await {
                Some(Wake::Changed) => break,
                Some(Wake::Owner(false)) => {}
                Some(Wake::Owner(true)) | None => return Ok(()),
            }
        }
    }
}

/// Reads the item's current state, cut to the limits the host enforces again.
async fn snapshot(item: &zbus::Proxy<'_>, id: &str) -> zbus::Result<pb::TrayItemChanged> {
    let title: String = item.get_property("Title").await.unwrap_or_default();
    let id_property: String = item.get_property("Id").await.unwrap_or_default();
    let status: String = item.get_property("Status").await.unwrap_or_default();
    let pixmaps: Vec<(i32, i32, Vec<u8>)> = item.get_property("IconPixmap").await.unwrap_or_default();
    let (icon_width, icon_height, icon_rgba) = best_icon(&pixmaps).unwrap_or_default();
    let label = if title.is_empty() { id_property } else { title };
    Ok(pb::TrayItemChanged {
        id: id.to_owned(),
        title: limits::clean(&label, limits::MAX_TITLE),
        icon_width,
        icon_height,
        icon_rgba,
        passive: status == "Passive",
    })
}

/// The largest valid pixmap within the size limit, converted to RGBA. `IconPixmap` carries ARGB32 in network byte
/// order, so each pixel's bytes are alpha, red, green, blue.
fn best_icon(pixmaps: &[(i32, i32, Vec<u8>)]) -> Option<(u32, u32, Vec<u8>)> {
    pixmaps
        .iter()
        .filter_map(|(w, h, data)| {
            let (w, h) = (u32::try_from(*w).ok()?, u32::try_from(*h).ok()?);
            let valid = w > 0 && h > 0 && w <= limits::MAX_TRAY_ICON_SIDE && h <= limits::MAX_TRAY_ICON_SIDE;
            (valid && data.len() as u64 == u64::from(w) * u64::from(h) * 4).then_some((w, h, data))
        })
        .max_by_key(|(w, h, _)| w * h)
        .map(|(w, h, data)| (w, h, data.chunks_exact(4).flat_map(|p| [p[1], p[2], p[3], p[0]]).collect()))
}

#[cfg(test)]
mod tests {
    use super::{Address, best_icon};

    #[test]
    fn a_bus_name_means_the_default_item_path() {
        let a = Address::parse("org.example.App", ":1.5").unwrap();
        assert_eq!((a.bus_name.as_str(), a.path.as_str()), ("org.example.App", "/StatusNotifierItem"));
    }

    #[test]
    fn an_object_path_lives_on_the_callers_connection() {
        let a = Address::parse("/org/ayatana/Item", ":1.5").unwrap();
        assert_eq!(a.id(), ":1.5/org/ayatana/Item");
    }

    #[test]
    fn empty_and_oversized_ids_are_refused() {
        assert!(Address::parse("/x", "").is_none());
        assert!(Address::parse(&"a".repeat(600), ":1.1").is_none());
    }

    #[test]
    fn argb_pixels_become_rgba() {
        let argb = vec![0xff, 1, 2, 3, 0x80, 4, 5, 6];
        let (w, h, rgba) = best_icon(&[(2, 1, argb)]).unwrap();
        assert_eq!((w, h, rgba), (2, 1, vec![1, 2, 3, 0xff, 4, 5, 6, 0x80]));
    }

    #[test]
    fn the_largest_valid_pixmap_wins_and_bad_ones_are_skipped() {
        let small = (1, 1, vec![0; 4]);
        let big = (2, 2, vec![0; 16]);
        let truncated = (4, 4, vec![0; 8]);
        let huge = (1024, 1024, vec![0; 4 * 1024 * 1024]);
        let negative = (-1, 1, vec![0; 4]);
        let (w, h, _) = best_icon(&[small, truncated, huge, negative, big]).unwrap();
        assert_eq!((w, h), (2, 2));
        assert!(best_icon(&[]).is_none());
    }
}
