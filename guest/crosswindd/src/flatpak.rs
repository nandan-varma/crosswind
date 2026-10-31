// SPDX-License-Identifier: AGPL-3.0-or-later
//! Flatpak operations on the user installation, through libflatpak.
//!
//! Everything here is blocking and runs on worker threads spawned by `control`; libflatpak
//! objects never leave the thread that created them.

use std::{
    cell::Cell,
    collections::HashSet,
    fs,
    io::{self, ErrorKind},
    path::{Path, PathBuf},
    rc::Rc,
};

use libflatpak::{Installation, Instance, RefKind, Remote, Transaction, gio, glib, prelude::*};

use crate::control_pb as pb;

pub const REMOTE: &str = "flathub";
pub const ARCH: &str = "aarch64";
pub const REPO_URL: &str = "https://dl.flathub.org/repo/flathub.flatpakrepo";
/// OpenPGP fingerprint of the Flathub signing key. A `.flatpakrepo` carrying any other key is refused.
pub const FLATHUB_KEY_FPR: &str = "6E5C05D979C76DAF93C081354184DD4D907A7CAE";

/// Metadata keys of the `[Context]` group that carry permissions.
const CONTEXT_KEYS: [&str; 5] = ["shared", "sockets", "devices", "filesystems", "features"];
const CONTEXT: &str = "Context";

/// What a transaction is asked to do.
pub enum Op {
    Install(String),
    Uninstall { app_id: String, delete_data: bool },
    /// Empty app id updates every installed app.
    Update(String),
}

pub enum Outcome {
    Done,
    Cancelled,
    Failed(String),
}

/// One progress report: `percent` covers the whole transaction, not the current operation.
pub struct Progress {
    pub phase: &'static str,
    pub detail: String,
    pub percent: u32,
    pub bytes_transferred: u64,
    pub bytes_total: u64,
}

/// Overall percent for operation `index` (0-based) of `total`, where `current` is that operation's own percent.
pub fn overall_percent(index: usize, total: usize, current: u32) -> u32 {
    if total == 0 {
        return 0;
    }
    let cur = current.min(100) as usize;
    let pct = (index.min(total) * 100 + cur) / total;
    pct.min(100) as u32
}

/// SHA-1 fingerprint (uppercase hex) of the primary OpenPGP key in a binary keyring.
/// Only v4 public-key packets are understood, which is all Flathub ships.
pub fn primary_fingerprint(keyring: &[u8]) -> Option<String> {
    let b0 = *keyring.first()?;
    if b0 & 0x80 == 0 {
        return None;
    }
    let (tag, body_len, hdr): (usize, usize, usize) = if b0 & 0x40 != 0 {
        let l = *keyring.get(1)? as usize;
        let (len, hdr) = match l {
            0..=191 => (l, 2),
            192..=223 => (((l - 192) << 8) + *keyring.get(2)? as usize + 192, 3),
            255 => (u32::from_be_bytes(keyring.get(2..6)?.try_into().ok()?) as usize, 6),
            _ => return None,
        };
        ((b0 & 0x3f) as usize, len, hdr)
    } else {
        let (len, hdr) = match b0 & 3 {
            0 => (*keyring.get(1)? as usize, 2),
            1 => (u16::from_be_bytes(keyring.get(1..3)?.try_into().ok()?) as usize, 3),
            2 => (u32::from_be_bytes(keyring.get(1..5)?.try_into().ok()?) as usize, 5),
            _ => return None,
        };
        (((b0 >> 2) & 0x0f) as usize, len, hdr)
    };
    if tag != 6 {
        return None;
    }
    let body = keyring.get(hdr..hdr.checked_add(body_len)?)?;
    if *body.first()? != 4 {
        return None;
    }
    let mut data = vec![0x99];
    data.extend_from_slice(&(body.len() as u16).to_be_bytes());
    data.extend_from_slice(body);
    let mut sum = glib::Checksum::new(glib::ChecksumType::Sha1)?;
    sum.update(&data);
    Some(sum.string()?.to_ascii_uppercase())
}

/// Extracts the binary keyring from a `.flatpakrepo` file and checks it is the pinned Flathub key.
pub fn check_flathub_key(repo: &[u8]) -> Result<Vec<u8>, String> {
    let kf = glib::KeyFile::new();
    kf.load_from_bytes(&glib::Bytes::from(repo), glib::KeyFileFlags::NONE)
        .map_err(|e| format!("flatpakrepo: {e}"))?;
    let b64 = kf.string("Flatpak Repo", "GPGKey").map_err(|_| "flatpakrepo has no GPGKey".to_string())?;
    let key = glib::base64_decode(&b64);
    match primary_fingerprint(&key) {
        Some(fpr) if fpr == FLATHUB_KEY_FPR => Ok(key),
        Some(fpr) => Err(format!("flatpakrepo key {fpr} is not the pinned Flathub key")),
        None => Err("flatpakrepo key is not a v4 OpenPGP key".into()),
    }
}

fn list(kf: &glib::KeyFile, key: &str) -> Vec<String> {
    kf.string(CONTEXT, key)
        .map(|s| s.split(';').filter(|e| !e.is_empty()).map(String::from).collect())
        .unwrap_or_default()
}

fn field<'a>(p: &'a pb::Permissions, key: &str) -> &'a Vec<String> {
    match key {
        "shared" => &p.shared,
        "sockets" => &p.sockets,
        "devices" => &p.devices,
        "filesystems" => &p.filesystems,
        _ => &p.features,
    }
}

fn field_mut<'a>(p: &'a mut pb::Permissions, key: &str) -> &'a mut Vec<String> {
    match key {
        "shared" => &mut p.shared,
        "sockets" => &mut p.sockets,
        "devices" => &mut p.devices,
        "filesystems" => &mut p.filesystems,
        _ => &mut p.features,
    }
}

/// Permissions in effect: the app's metadata with the override applied (`!entry` removes).
pub fn effective(base: &glib::KeyFile, over: &glib::KeyFile) -> pb::Permissions {
    let mut out = pb::Permissions::default();
    for key in CONTEXT_KEYS {
        let mut entries = list(base, key);
        for e in list(over, key) {
            match e.strip_prefix('!') {
                Some(gone) => entries.retain(|x| x != gone),
                None if !entries.contains(&e) => entries.push(e),
                None => {}
            }
        }
        *field_mut(&mut out, key) = entries;
    }
    out
}

/// Per-key override entries that turn the metadata `base` into `want`.
fn delta(base: &glib::KeyFile, want: &pb::Permissions) -> Vec<(&'static str, Vec<String>)> {
    CONTEXT_KEYS
        .iter()
        .map(|&key| {
            let have = list(base, key);
            let wanted = field(want, key);
            let mut entries: Vec<String> = wanted.iter().filter(|w| !have.contains(w)).cloned().collect();
            entries.extend(have.iter().filter(|h| !wanted.contains(h)).map(|h| format!("!{h}")));
            (key, entries)
        })
        .collect()
}

/// Writes the override for `app_id` into `dir` (Flatpak's override keyfile format), so that the
/// effective permissions equal `want`. Other groups in an existing override file are kept; an
/// override that ends up empty is removed.
pub fn write_override(dir: &Path, app_id: &str, base: &glib::KeyFile, want: &pb::Permissions) -> io::Result<()> {
    let path = dir.join(app_id);
    let kf = read_override(dir, app_id)?;
    for (key, entries) in delta(base, want) {
        if entries.is_empty() {
            let _ = kf.remove_key(CONTEXT, key);
        } else {
            kf.set_string(CONTEXT, key, &format!("{};", entries.join(";")));
        }
    }
    if kf.keys(CONTEXT).map(|k| k.is_empty()).unwrap_or(true) {
        let _ = kf.remove_group(CONTEXT);
    }
    if kf.groups().is_empty() {
        match fs::remove_file(&path) {
            Err(e) if e.kind() != ErrorKind::NotFound => return Err(e),
            _ => return Ok(()),
        }
    }
    fs::create_dir_all(dir)?;
    kf.save_to_file(&path).map_err(io_err)
}

/// Reads the override file for `app_id` from `dir`; an absent file is an empty override.
pub fn read_override(dir: &Path, app_id: &str) -> io::Result<glib::KeyFile> {
    let kf = glib::KeyFile::new();
    let path = dir.join(app_id);
    if path.exists() {
        kf.load_from_file(&path, glib::KeyFileFlags::NONE).map_err(io_err)?;
    }
    Ok(kf)
}

fn io_err(e: glib::Error) -> io::Error {
    io::Error::other(e.to_string())
}

fn s<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

/// The user installation, opened on the calling thread.
pub fn user_installation() -> Result<Installation, String> {
    Installation::new_user(None::<&gio::Cancellable>).map_err(s)
}

fn installation_dir(inst: &Installation) -> Result<PathBuf, String> {
    inst.path().and_then(|f| f.path()).ok_or_else(|| "user installation has no path".into())
}

/// Adds the pinned Flathub remote if the user installation does not have it yet.
pub fn ensure_remote(inst: &Installation) -> Result<(), String> {
    if inst.remote_by_name(REMOTE, None::<&gio::Cancellable>).is_ok() {
        return Ok(());
    }
    let out = std::process::Command::new("curl").args(["-fsSL", REPO_URL]).output().map_err(s)?;
    if !out.status.success() {
        return Err(format!("fetching {REPO_URL} failed"));
    }
    check_flathub_key(&out.stdout)?;
    let remote = Remote::from_file(REMOTE, &glib::Bytes::from(&out.stdout)).map_err(s)?;
    inst.add_remote(&remote, false, None::<&gio::Cancellable>).map_err(s)
}

fn is_app(kind: RefKind) -> bool {
    kind == RefKind::App
}

fn find_installed(inst: &Installation, app_id: &str) -> Result<libflatpak::InstalledRef, String> {
    inst.list_installed_refs(None::<&gio::Cancellable>)
        .map_err(s)?
        .into_iter()
        .find(|r| is_app(r.kind()) && r.name().as_deref() == Some(app_id))
        .ok_or_else(|| format!("{app_id} is not installed"))
}

pub fn list_installed() -> Result<Vec<pb::InstalledApp>, String> {
    let inst = user_installation()?;
    let updates: HashSet<String> = inst
        .list_installed_refs_for_update(None::<&gio::Cancellable>)
        .map_err(s)?
        .iter()
        .filter_map(|r| r.name().map(|n| n.to_string()))
        .collect();
    let apps = inst
        .list_installed_refs(None::<&gio::Cancellable>)
        .map_err(s)?
        .into_iter()
        .filter(|r| is_app(r.kind()))
        .map(|r| {
            let app_id = r.name().map(|n| n.to_string()).unwrap_or_default();
            pb::InstalledApp {
                name: r.appdata_name().map(|n| n.to_string()).unwrap_or_else(|| app_id.clone()),
                version: r.appdata_version().map(|v| v.to_string()).unwrap_or_default(),
                branch: r.branch().map(|b| b.to_string()).unwrap_or_default(),
                installed_size: r.installed_size(),
                update_available: updates.contains(&app_id),
                app_id,
            }
        })
        .collect();
    Ok(apps)
}

pub fn refresh_catalog() -> Result<(), String> {
    let inst = user_installation()?;
    ensure_remote(&inst)?;
    inst.update_appstream_sync(REMOTE, Some(ARCH), None::<&gio::Cancellable>).map_err(s)
}

/// The cached Flathub AppStream catalog, gzip-compressed, as Flatpak wrote it.
pub fn read_catalog() -> Result<Vec<u8>, String> {
    let inst = user_installation()?;
    let path = installation_dir(&inst)?.join(format!("appstream/{REMOTE}/{ARCH}/active/appstream.xml.gz"));
    fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))
}

pub fn get_permissions(app_id: &str) -> Result<pb::Permissions, String> {
    let inst = user_installation()?;
    let installed = find_installed(&inst, app_id)?;
    let base = glib::KeyFile::new();
    base.load_from_bytes(&installed.load_metadata(None::<&gio::Cancellable>).map_err(s)?, glib::KeyFileFlags::NONE)
        .map_err(s)?;
    let over = glib::KeyFile::new();
    let text = inst.load_app_overrides(app_id, None::<&gio::Cancellable>).map_err(s)?;
    over.load_from_data(&text, glib::KeyFileFlags::NONE).map_err(s)?;
    Ok(effective(&base, &over))
}

pub fn set_permissions(app_id: &str, want: &pb::Permissions) -> Result<(), String> {
    let inst = user_installation()?;
    let installed = find_installed(&inst, app_id)?;
    let base = glib::KeyFile::new();
    base.load_from_bytes(&installed.load_metadata(None::<&gio::Cancellable>).map_err(s)?, glib::KeyFileFlags::NONE)
        .map_err(s)?;
    write_override(&installation_dir(&inst)?.join("overrides"), app_id, &base, want).map_err(s)
}

pub fn list_running() -> Vec<pb::RunningApp> {
    Instance::all()
        .into_iter()
        .filter_map(|i| {
            Some(pb::RunningApp { app_id: i.app()?.to_string(), pid: i.pid().max(0) as u32 })
        })
        .collect()
}

/// Remote ref string (`app/<id>/<arch>/<branch>`) for an app on the Flathub remote.
fn remote_ref(inst: &Installation, app_id: &str) -> Result<String, String> {
    let refs = inst.list_remote_refs_sync(REMOTE, None::<&gio::Cancellable>).map_err(s)?;
    let mut matches = refs
        .iter()
        .filter(|r| is_app(r.kind()) && r.name().as_deref() == Some(app_id) && r.arch().as_deref() == Some(ARCH));
    let chosen = matches.clone().find(|r| r.branch().as_deref() == Some("stable")).or_else(|| matches.next());
    let branch = chosen.and_then(|r| r.branch()).ok_or_else(|| format!("{app_id} not found on {REMOTE} for {ARCH}"))?;
    Ok(format!("app/{app_id}/{ARCH}/{branch}"))
}

fn phase_of(t: libflatpak::TransactionOperationType) -> &'static str {
    use libflatpak::TransactionOperationType as T;
    match t {
        T::Uninstall => "uninstall",
        T::Update => "update",
        _ => "install",
    }
}

fn attach_progress(tx: &Transaction, progress: impl Fn(Progress) + 'static) {
    let progress = Rc::new(progress);
    let total = Rc::new(Cell::new(0usize));
    let bytes_total = Rc::new(Cell::new(0u64));
    let index = Rc::new(Cell::new(0usize));
    {
        let (total, bytes_total) = (total.clone(), bytes_total.clone());
        tx.connect_ready(move |t| {
            let ops = t.operations();
            total.set(ops.len());
            bytes_total.set(ops.iter().map(|o| o.download_size()).sum());
            true
        });
    }
    tx.connect_new_operation(move |_, op, prog| {
        let idx = index.replace(index.get() + 1);
        let phase = phase_of(op.operation_type());
        let detail = op.get_ref().map(|r| r.to_string()).unwrap_or_default();
        let (progress, total, bytes_total) = (progress.clone(), total.clone(), bytes_total.clone());
        prog.connect_changed(move |p| {
            progress(Progress {
                phase,
                detail: detail.clone(),
                percent: overall_percent(idx, total.get(), p.progress().max(0) as u32),
                bytes_transferred: p.bytes_transferred(),
                bytes_total: bytes_total.get(),
            })
        });
    });
}

/// Runs one install, uninstall or update to completion or cancellation. Blocking.
pub fn run_op(op: &Op, cancel: &gio::Cancellable, progress: impl Fn(Progress) + 'static) -> Outcome {
    let result = (|| -> Result<(), String> {
        let inst = user_installation()?;
        ensure_remote(&inst)?;
        let tx = Transaction::for_installation(&inst, None::<&gio::Cancellable>).map_err(s)?;
        tx.set_no_interaction(true);
        tx.add_default_dependency_sources();
        match op {
            Op::Install(app_id) => {
                let r = remote_ref(&inst, app_id)?;
                tx.add_install(REMOTE, &r, &[]).map_err(s)?;
            }
            Op::Uninstall { app_id, .. } => {
                let r = find_installed(&inst, app_id)?.format_ref().ok_or("no ref")?;
                tx.add_uninstall(&r).map_err(s)?;
            }
            Op::Update(app_id) => {
                for r in inst.list_installed_refs_for_update(None::<&gio::Cancellable>).map_err(s)? {
                    if app_id.is_empty() || r.name().as_deref() == Some(app_id.as_str()) {
                        let rs = r.format_ref().ok_or("no ref")?;
                        tx.add_update(&rs, &[], None).map_err(s)?;
                    }
                }
            }
        }
        attach_progress(&tx, progress);
        tx.run(Some(cancel)).map_err(s)?;
        if let Op::Uninstall { app_id, delete_data: true } = op {
            let data = PathBuf::from(std::env::var("HOME").map_err(s)?).join(".var/app").join(app_id);
            match fs::remove_dir_all(&data) {
                Err(e) if e.kind() != ErrorKind::NotFound => return Err(format!("{}: {e}", data.display())),
                _ => {}
            }
        }
        Ok(())
    })();
    match result {
        Ok(()) => Outcome::Done,
        Err(_) if cancel.is_cancelled() => Outcome::Cancelled,
        Err(e) => Outcome::Failed(e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kf(data: &str) -> glib::KeyFile {
        let kf = glib::KeyFile::new();
        kf.load_from_data(data, glib::KeyFileFlags::NONE).expect("valid keyfile");
        kf
    }

    fn perms(sockets: &[&str], shared: &[&str]) -> pb::Permissions {
        pb::Permissions {
            sockets: sockets.iter().map(|s| s.to_string()).collect(),
            shared: shared.iter().map(|s| s.to_string()).collect(),
            ..Default::default()
        }
    }

    fn sorted(mut p: pb::Permissions) -> pb::Permissions {
        for key in CONTEXT_KEYS {
            field_mut(&mut p, key).sort();
        }
        p
    }

    #[test]
    fn percent_spreads_operations_evenly() {
        assert_eq!(overall_percent(0, 0, 50), 0);
        assert_eq!(overall_percent(0, 1, 0), 0);
        assert_eq!(overall_percent(0, 1, 100), 100);
        assert_eq!(overall_percent(1, 4, 50), 37);
        assert_eq!(overall_percent(3, 4, 100), 100);
        assert_eq!(overall_percent(2, 4, 250), 75);
    }

    #[test]
    fn non_key_packet_has_no_fingerprint() {
        assert_eq!(primary_fingerprint(&[]), None);
        // A user-id packet (tag 13), not a key.
        assert_eq!(primary_fingerprint(&[0xC0 | 13, 3, 4, 0, 0]), None);
    }

    #[test]
    fn v4_key_packet_fingerprint_is_sha1_of_key_body() {
        let body = [4u8, 0, 0, 0, 1, 1, 0, 0, 0];
        let mut packet = vec![0xC0 | 6, body.len() as u8];
        packet.extend_from_slice(&body);
        let fpr = primary_fingerprint(&packet).expect("v4 key");
        assert_eq!(fpr.len(), 40);
        assert!(fpr.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_lowercase()));
        let mut other = packet.clone();
        *other.last_mut().unwrap() = 1;
        assert_ne!(primary_fingerprint(&other), Some(fpr));
    }

    #[test]
    fn override_roundtrip_keeps_effective_permissions() {
        let base = kf("[Context]\nshared=network;ipc;\nsockets=x11;wayland;fallback-x11;\n");
        let want = perms(&["wayland", "pulseaudio"], &["network"]);
        let dir = std::env::temp_dir().join(format!("cw-override-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);

        write_override(&dir, "org.example.App", &base, &want).expect("write");
        let over = read_override(&dir, "org.example.App").expect("read");
        let text = over.to_data();
        assert!(text.contains("!x11"), "override removes x11: {text}");
        assert!(text.contains("!ipc"), "override removes ipc: {text}");
        assert_eq!(sorted(effective(&base, &over)), sorted(want.clone()));

        // Clearing back to the metadata defaults removes the file entirely.
        write_override(&dir, "org.example.App", &base, &sorted(effective(&base, &kf("")))).expect("clear");
        assert!(!dir.join("org.example.App").exists());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn override_keeps_unrelated_groups() {
        let base = kf("[Context]\nshared=network;\n");
        let dir = std::env::temp_dir().join(format!("cw-override-keep-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("app.x"), "[Environment]\nFOO=bar\n").unwrap();

        write_override(&dir, "app.x", &base, &perms(&[], &[])).expect("write");
        let over = read_override(&dir, "app.x").expect("read");
        assert_eq!(over.string("Environment", "FOO").unwrap(), "bar");
        assert_eq!(over.string(CONTEXT, "shared").unwrap(), "!network;");
        let _ = fs::remove_dir_all(&dir);
    }

    /// Needs network: fetches the live Flathub repo file and checks its key against the pin.
    #[test]
    #[ignore]
    fn live_flathub_repo_key_matches_pin() {
        let out = std::process::Command::new("curl").args(["-fsSL", REPO_URL]).output().expect("curl");
        assert!(out.status.success());
        check_flathub_key(&out.stdout).expect("pinned key");
    }

    #[test]
    fn effective_without_override_is_metadata() {
        let base = kf("[Context]\nsockets=x11;\nfilesystems=xdg-download:ro;\n");
        let p = effective(&base, &kf(""));
        assert_eq!(p.sockets, vec!["x11".to_string()]);
        assert_eq!(p.filesystems, vec!["xdg-download:ro".to_string()]);
        assert!(p.shared.is_empty());
    }
}
