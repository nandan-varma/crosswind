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
const MENU_INTERFACE: &str = "com.canonical.dbusmenu";
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

    /// Forwards a choice in the menu the host showed for `id` to the app (dbusmenu `Event` "clicked").
    pub fn menu_click(&self, id: &str, entry: i32) {
        let Some(address) = lock(&self.items).get(id).cloned() else { return };
        let conn = self.conn.clone();
        thread::spawn(move || {
            let result = zbus::block_on(async {
                let item = zbus::Proxy::new(&conn, address.bus_name.as_str(), address.path.as_str(), ITEM_INTERFACE).await?;
                let path: zbus::OwnedObjectPath = item.get_property("Menu").await?;
                let menu = zbus::Proxy::new(&conn, address.bus_name.as_str(), path, MENU_INTERFACE).await?;
                let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
                menu.call_method("Event", &(entry, "clicked", zbus::Variant::from(0i32), now.as_secs() as u32)).await
            });
            if let Err(e) = result {
                tracing::debug!("tray menu click not delivered: {e}");
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
    // The app's menu, when it has one: its layout changes wake the loop like the item's own signals.
    let menu = menu_proxy(conn, &item, address).await;
    let menu_signals = match &menu {
        Some(menu) => menu.receive_all_signals().await?.map(|_| Wake::Changed).boxed(),
        None => stream::empty().boxed(),
    };
    let mut wakes = stream::select(stream::select(signals, owner), menu_signals);
    loop {
        if !dbus.name_has_owner(name.clone()).await? {
            return Ok(());
        }
        let changed = snapshot(&item, menu.as_ref(), id).await?;
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
async fn snapshot(item: &zbus::Proxy<'_>, menu: Option<&zbus::Proxy<'_>>, id: &str) -> zbus::Result<pb::TrayItemChanged> {
    let title: String = item.get_property("Title").await.unwrap_or_default();
    let id_property: String = item.get_property("Id").await.unwrap_or_default();
    let status: String = item.get_property("Status").await.unwrap_or_default();
    let pixmaps: Vec<(i32, i32, Vec<u8>)> = item.get_property("IconPixmap").await.unwrap_or_default();
    let (icon_width, icon_height, icon_rgba) = best_icon(&pixmaps).unwrap_or_default();
    let label = if title.is_empty() { id_property } else { title };
    let menu_on_activate: bool = item.get_property("ItemIsMenu").await.unwrap_or_default();
    let menu = match menu {
        Some(menu) => read_menu(menu).await.unwrap_or_default(),
        None => Vec::new(),
    };
    Ok(pb::TrayItemChanged {
        id: id.to_owned(),
        title: limits::clean(&label, limits::MAX_TITLE),
        icon_width,
        icon_height,
        icon_rgba,
        passive: status == "Passive",
        menu,
        menu_on_activate,
    })
}

/// The item's `com.canonical.dbusmenu` object, when it names one.
async fn menu_proxy<'a>(conn: &'a Connection, item: &zbus::Proxy<'_>, address: &Address) -> Option<zbus::Proxy<'a>> {
    let path: zbus::OwnedObjectPath = item.get_property("Menu").await.ok()?;
    if path.as_str() == "/" {
        return None;
    }
    zbus::Proxy::new(conn, address.bus_name.clone(), path, MENU_INTERFACE).await.ok()
}

/// The menu's top level, read after `AboutToShow` (many apps build their menu lazily), cut to the limits the host
/// enforces again.
async fn read_menu(menu: &zbus::Proxy<'_>) -> zbus::Result<Vec<pb::TrayMenuItem>> {
    let _ = menu.call_method("AboutToShow", &(0i32,)).await;
    type Layout = (i32, HashMap<String, zbus::OwnedVariant>, Vec<zbus::OwnedVariant>);
    let (_revision, layout): (u32, Layout) = menu.call("GetLayout", &(0i32, -1i32, Vec::<String>::new())).await?;
    let mut budget = limits::MAX_TRAY_MENU_ITEMS;
    Ok(parse_layout(&zbus::Variant::from(layout), 0, &mut budget).map(|root| root.children).unwrap_or_default())
}

/// One dbusmenu node `(id, properties, children)`. `depth` 0 is the invisible root. Entries beyond the depth or the
/// total budget are dropped, as are hidden ones.
fn parse_layout(value: &zbus::Variant<'_>, depth: usize, budget: &mut usize) -> Option<pb::TrayMenuItem> {
    parse_node(unwrap(value), depth, budget)
}

fn parse_node(value: &zbus::Variant<'_>, depth: usize, budget: &mut usize) -> Option<pb::TrayMenuItem> {
    use zbus::Variant as Value;
    let Value::Structure(node) = value else { return None };
    let [Value::I32(id), Value::Dict(props), Value::Array(children)] = node.fields() else { return None };
    let props: HashMap<String, &Value<'_>> = props
        .iter()
        .filter_map(|(k, v)| match k {
            Value::Str(s) => Some((s.to_string(), unwrap(v))),
            _ => None,
        })
        .collect();
    let get = |key: &str| props.get(key).copied();
    let flag = |key: &str, default: bool| match get(key) {
        Some(Value::Bool(b)) => *b,
        _ => default,
    };
    if depth > 0 {
        if !flag("visible", true) || *budget == 0 {
            return None;
        }
        *budget -= 1;
    }
    let text = |key: &str| match get(key) {
        Some(Value::Str(s)) => s.to_string(),
        _ => String::new(),
    };
    let toggle = text("toggle-type");
    let check = match (toggle.as_str(), get("toggle-state")) {
        ("checkmark" | "radio", Some(Value::I32(1))) => pb::tray_menu_item::Check::On,
        ("checkmark" | "radio", _) => pb::tray_menu_item::Check::Off,
        _ => pb::tray_menu_item::Check::None,
    };
    let mut item = pb::TrayMenuItem {
        id: *id,
        label: limits::clean(&unmnemonic(&text("label")), limits::MAX_TITLE),
        enabled: flag("enabled", true),
        separator: text("type") == "separator",
        check: check as i32,
        children: Vec::new(),
    };
    if depth < limits::MAX_TRAY_MENU_DEPTH {
        item.children = children.iter().filter_map(|child| parse_layout(child, depth + 1, budget)).collect();
    }
    Some(item)
}

/// Variants nest: `a{sv}` values and `av` children arrive wrapped.
fn unwrap<'a, 'v>(value: &'a zbus::Variant<'v>) -> &'a zbus::Variant<'v> {
    match value {
        zbus::Variant::Variant(inner) => unwrap(inner),
        other => other,
    }
}

/// dbusmenu labels mark the keyboard mnemonic with `_`; `__` is a literal underscore.
fn unmnemonic(label: &str) -> String {
    let mut out = String::with_capacity(label.len());
    let mut chars = label.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '_' {
            if chars.peek() == Some(&'_') {
                out.push('_');
                chars.next();
            }
        } else {
            out.push(c);
        }
    }
    out
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
    /// A dbusmenu node as the wire carries it: `(i, a{sv}, av)`, children wrapped in variants.
    fn node(id: i32, props: &[(&str, Variant<'static>)], children: Vec<Variant<'static>>) -> Variant<'static> {
        let props: HashMap<String, Variant<'static>> =
            props.iter().map(|(k, v)| ((*k).to_owned(), Variant::Variant(Box::new(v.clone())))).collect();
        let children: Vec<Variant<'static>> = children.into_iter().map(|c| Variant::Variant(Box::new(c))).collect();
        Variant::Structure(
            zbus::Structure::builder()
                .add_field(id)
                .append_field(Variant::from(props))
                .append_field(Variant::from(children))
                .build()
                .expect("structure"),
        )
    }

    #[test]
    fn a_dbusmenu_layout_becomes_the_hosts_menu() {
        let layout = node(
            0,
            &[],
            vec![
                node(1, &[("label", Variant::from("_Open"))], vec![]),
                node(2, &[("type", Variant::from("separator"))], vec![]),
                node(
                    3,
                    &[("label", Variant::from("Muted")), ("toggle-type", Variant::from("checkmark")), ("toggle-state", Variant::from(1i32))],
                    vec![],
                ),
                node(4, &[("label", Variant::from("Hidden")), ("visible", Variant::from(false))], vec![]),
                node(5, &[("label", Variant::from("More")), ("enabled", Variant::from(false))], vec![node(6, &[("label", Variant::from("Sub"))], vec![])]),
            ],
        );
        let mut budget = 128;
        let root = parse_layout(&layout, 0, &mut budget).expect("root");
        let labels: Vec<_> = root.children.iter().map(|c| (c.id, c.label.as_str(), c.separator, c.enabled)).collect();
        assert_eq!(labels, [(1, "Open", false, true), (2, "", true, true), (3, "Muted", false, true), (5, "More", false, false)]);
        assert_eq!(root.children[2].check, crate::control_pb::tray_menu_item::Check::On as i32);
        assert_eq!(root.children[3].children[0].label, "Sub");
    }

    #[test]
    fn a_hostile_layout_is_cut_to_the_budget_and_depth() {
        let mut deep = node(1, &[("label", Variant::from("x"))], vec![]);
        for id in 2..20 {
            deep = node(id, &[("label", Variant::from("x"))], vec![deep]);
        }
        let mut budget = 128;
        let root = parse_layout(&node(0, &[], vec![deep]), 0, &mut budget).expect("root");
        let mut levels = 0;
        let mut at = &root;
        while let Some(child) = at.children.first() {
            levels += 1;
            at = child;
        }
        assert_eq!(levels, crate::limits::MAX_TRAY_MENU_DEPTH);

        let wide: Vec<_> = (1..400).map(|i| node(i, &[("label", Variant::from("x"))], vec![])).collect();
        let mut budget = crate::limits::MAX_TRAY_MENU_ITEMS;
        let root = parse_layout(&node(0, &[], wide), 0, &mut budget).expect("root");
        assert_eq!(root.children.len(), crate::limits::MAX_TRAY_MENU_ITEMS);
    }

    #[test]
    fn mnemonic_markers_go_and_double_underscores_stay() {
        assert_eq!(unmnemonic("_Open"), "Open");
        assert_eq!(unmnemonic("Save __as"), "Save _as");
    }

    use std::collections::HashMap;

    use zbus::Variant;

    use super::{Address, best_icon, parse_layout, unmnemonic};

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

    /// The whole path on a private session bus: a fake app registers an item with a dbusmenu, the watcher mirrors the
    /// menu to the host's events, and a menu choice reaches the app as a dbusmenu `Event`. Needs `dbus-daemon`.
    #[test]
    #[ignore = "needs dbus-daemon; run with --ignored"]
    fn a_registered_item_and_its_menu_round_trip_over_the_bus() {
        use std::{
            io::{BufRead, BufReader},
            process::{Command, Stdio},
            sync::{Arc, Mutex},
            time::{Duration, Instant},
        };

        use smithay::reexports::calloop::{EventLoop, channel};
        use zbus::{connection::Builder, interface};

        use crate::{control::Note, control_pb::{self as pb, event}};

        struct Item;
        #[interface(name = "org.kde.StatusNotifierItem")]
        impl Item {
            #[zbus(property)]
            fn id(&self) -> String {
                "fake".into()
            }
            #[zbus(property)]
            fn title(&self) -> String {
                "Fake".into()
            }
            #[zbus(property)]
            fn status(&self) -> String {
                "Active".into()
            }
            #[zbus(property)]
            fn menu(&self) -> zbus::OwnedObjectPath {
                zbus::OwnedObjectPath::try_from("/MenuBar").expect("path")
            }
        }

        type Layout = (i32, HashMap<String, zbus::OwnedVariant>, Vec<zbus::OwnedVariant>);
        struct Menu(Arc<Mutex<Vec<(i32, String)>>>);
        #[interface(name = "com.canonical.dbusmenu")]
        impl Menu {
            fn get_layout(&self, _parent: i32, _depth: i32, _props: Vec<String>) -> (u32, Layout) {
                let leaf = |id: i32, label: &str| -> zbus::OwnedVariant {
                    let props: HashMap<String, zbus::OwnedVariant> =
                        [("label".to_owned(), zbus::OwnedVariant::try_from(zbus::Variant::from(label)).expect("label"))].into();
                    let node: Layout = (id, props, Vec::new());
                    zbus::OwnedVariant::try_from(zbus::Variant::from(node)).expect("node")
                };
                (1, (0, HashMap::new(), vec![leaf(1, "_Open"), leaf(2, "Quit")]))
            }
            fn about_to_show(&self, _id: i32) -> bool {
                false
            }
            fn event(&self, id: i32, kind: String, _data: zbus::OwnedVariant, _timestamp: u32) {
                self.0.lock().expect("events").push((id, kind));
            }
        }

        let mut daemon = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon");
        let mut address = String::new();
        BufReader::new(daemon.stdout.take().expect("stdout")).read_line(&mut address).expect("address");
        let address = address.trim().to_owned();

        let mut event_loop: EventLoop<Vec<Note>> = EventLoop::try_new().expect("loop");
        let (notes_tx, notes_rx) = channel::channel::<Note>();
        event_loop
            .handle()
            .insert_source(notes_rx, |event, _, notes| {
                if let channel::Event::Msg(note) = event {
                    notes.push(note);
                }
            })
            .expect("source");
        let tray = super::Tray::start(&address, notes_tx).expect("watcher");

        let events = Arc::new(Mutex::new(Vec::new()));
        let app = zbus::block_on(
            Builder::address(address.as_str())
                .serve_at("/StatusNotifierItem", Item)
                .serve_at("/MenuBar", Menu(events.clone()))
                .build(),
        )
        .expect("app connection");
        let unique = app.unique_name().expect("name").to_string();
        zbus::block_on(app.call_method(
            Some(super::WATCHER_NAME),
            super::WATCHER_PATH,
            Some(super::WATCHER_NAME),
            "RegisterStatusNotifierItem",
            &(unique.as_str(),),
        ))
        .expect("register");

        let mut notes = Vec::new();
        let deadline = Instant::now() + Duration::from_secs(10);
        let mirrored = loop {
            event_loop.dispatch(Duration::from_millis(100), &mut notes).expect("dispatch");
            let found = notes.iter().find_map(|n| match n {
                Note::Event(pb::Event { body: Some(event::Body::TrayItemChanged(c)) }) if !c.menu.is_empty() => Some(c.clone()),
                _ => None,
            });
            if let Some(found) = found {
                break found;
            }
            assert!(Instant::now() < deadline, "the item was never mirrored with a menu");
        };
        let labels: Vec<_> = mirrored.menu.iter().map(|m| (m.id, m.label.as_str())).collect();
        assert_eq!(labels, [(1, "Open"), (2, "Quit")]);

        tray.menu_click(&mirrored.id, 2);
        let deadline = Instant::now() + Duration::from_secs(10);
        while events.lock().expect("events").is_empty() {
            assert!(Instant::now() < deadline, "the menu click never arrived");
            std::thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(events.lock().expect("events")[0], (2, "clicked".to_owned()));
        let _ = daemon.kill();
        let _ = daemon.wait();
    }
}
