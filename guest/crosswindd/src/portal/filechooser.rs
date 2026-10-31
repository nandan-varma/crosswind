// SPDX-License-Identifier: AGPL-3.0-or-later
//! `org.freedesktop.impl.portal.FileChooser`: OpenFile, SaveFile and SaveFiles. The host shows the
//! native Open/Save panel (`Call::FileChooser`) and answers with guest paths inside its shared
//! folders; this backend returns them as `file://` URIs. Advanced options (choices, current folder,
//! and so on) are ignored.
//!
//! The user may take minutes, so the wait runs on its own thread and the zbus method awaits a
//! oneshot. The zbus executor is never blocked.

use std::{collections::HashMap, thread, time::Duration};

use futures_channel::oneshot;
use zbus::{OwnedVariant, Variant, fdo, interface, ObjectPath};

use super::Bridge;
use crate::control_pb::{self as pb, call, call_reply};

/// How long the user may take to answer the panel before the call gives up.
pub const CHOOSER_TIMEOUT: Duration = Duration::from_secs(600);

/// Portal response codes (`org.freedesktop.portal.Request`).
const RESPONSE_SUCCESS: u32 = 0;
const RESPONSE_CANCELLED: u32 = 1;
const RESPONSE_OTHER: u32 = 2;

/// Which panel the host should show.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Open,
    Save,
    OpenDirectory,
}

/// The parts of the portal options that the host understands.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Options {
    pub multiple: bool,
    pub directory: bool,
    /// Glob patterns (`*.png`) and MIME types (`image/png`), flattened from the `filters` option.
    pub filters: Vec<String>,
    pub current_name: String,
    pub accept_label: String,
    /// The `files` option of SaveFiles: file names to save into the chosen folder.
    pub files: Vec<String>,
}

/// Flattens the portal's `a(sa(us))` filter list. Each filter contributes its patterns in order:
/// type 0 is a glob, type 1 a MIME type. Unknown types are dropped.
pub fn parse_filters(filters: &[(String, Vec<(u32, String)>)]) -> Vec<String> {
    filters
        .iter()
        .flat_map(|(_, patterns)| patterns.iter())
        .filter(|(kind, pattern)| matches!(kind, 0 | 1) && !pattern.is_empty())
        .map(|(_, pattern)| pattern.clone())
        .collect()
}

/// Reads the options a{sv} dict. Missing or mistyped keys keep their defaults.
pub fn parse_options(options: &HashMap<String, OwnedVariant>) -> Options {
    let flag = |key: &str| options.get(key).and_then(|v| bool::try_from(v.clone()).ok()).unwrap_or(false);
    let text = |key: &str| options.get(key).and_then(|v| String::try_from(v.clone()).ok()).unwrap_or_default();
    let filters = options
        .get("filters")
        .and_then(|v| <Vec<(String, Vec<(u32, String)>)>>::try_from(v.clone()).ok())
        .map(|f| parse_filters(&f))
        .unwrap_or_default();
    let files = options
        .get("files")
        .and_then(|v| <Vec<Vec<u8>>>::try_from(v.clone()).ok())
        .unwrap_or_default()
        .into_iter()
        .filter_map(|name| String::from_utf8(name).ok())
        .filter(|name| !name.is_empty() && !name.contains('/'))
        .collect();
    Options {
        multiple: flag("multiple"),
        directory: flag("directory"),
        filters,
        current_name: text("current_name"),
        accept_label: text("accept_label"),
        files,
    }
}

/// The host panel for a portal method. `OpenFile` with `directory` picks a folder.
/// `SaveFiles` picks a folder too: the app writes each named file into it.
pub fn kind_for(method: Method, options: &Options) -> Kind {
    match method {
        Method::OpenFile if options.directory => Kind::OpenDirectory,
        Method::OpenFile => Kind::Open,
        Method::SaveFile => Kind::Save,
        Method::SaveFiles => Kind::OpenDirectory,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Method {
    OpenFile,
    SaveFile,
    SaveFiles,
}

/// What the portal answers once the host has replied.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    Uris(Vec<String>),
    Cancelled,
    Failed(String),
}

/// Turns the host's reply into portal URIs. For SaveFiles, every returned folder gets each requested
/// file name appended.
pub fn outcome(reply: Result<pb::CallReply, String>, method: Method, files: &[String]) -> Outcome {
    let reply = match reply {
        Ok(reply) => reply,
        Err(e) => return Outcome::Failed(e),
    };
    match reply.result {
        Some(call_reply::Result::FileChooser(result)) if result.cancelled || result.paths.is_empty() => {
            Outcome::Cancelled
        }
        Some(call_reply::Result::FileChooser(result)) => {
            let paths = match method {
                Method::SaveFiles => result
                    .paths
                    .iter()
                    .flat_map(|dir| files.iter().map(move |name| format!("{}/{name}", dir.trim_end_matches('/'))))
                    .collect(),
                _ => result.paths,
            };
            Outcome::Uris(paths.iter().map(|p| file_uri(p)).collect())
        }
        Some(call_reply::Result::Error(e)) => Outcome::Failed(e.message),
        _ => Outcome::Failed("unexpected host reply".to_owned()),
    }
}

/// `file://` URI for an absolute guest path. Every byte outside the unreserved set and `/` is
/// percent-encoded.
pub fn file_uri(path: &str) -> String {
    let mut uri = String::from("file://");
    for byte in path.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => uri.push(byte as char),
            _ => uri.push_str(&format!("%{byte:02X}")),
        }
    }
    uri
}

pub struct FileChooser {
    pub bridge: Bridge,
}

impl FileChooser {
    async fn run(
        &self,
        method: Method,
        app_id: &str,
        title: &str,
        options: HashMap<String, OwnedVariant>,
    ) -> (u32, HashMap<String, OwnedVariant>) {
        let parsed = parse_options(&options);
        let body = call::Body::FileChooser(pb::FileChooser {
            mode: match kind_for(method, &parsed) {
                Kind::Open => pb::file_chooser::Mode::Open,
                Kind::Save => pb::file_chooser::Mode::Save,
                Kind::OpenDirectory => pb::file_chooser::Mode::OpenDirectory,
            } as i32,
            title: title.to_owned(),
            multiple: parsed.multiple,
            filters: parsed.filters.clone(),
            suggested_name: parsed.current_name.clone(),
            accept_label: parsed.accept_label.clone(),
        });
        let (tx, rx) = oneshot::channel();
        let bridge = self.bridge.clone();
        let app_id = app_id.to_owned();
        thread::spawn(move || {
            let _ = tx.send(bridge.call_blocking_for(&app_id, body, CHOOSER_TIMEOUT));
        });
        let reply = rx.await.unwrap_or_else(|_| Err("file chooser thread gone".to_owned()));
        let (response, uris) = match outcome(reply, method, &parsed.files) {
            Outcome::Uris(uris) => (RESPONSE_SUCCESS, uris),
            Outcome::Cancelled => (RESPONSE_CANCELLED, Vec::new()),
            Outcome::Failed(e) => {
                tracing::warn!("file chooser failed: {e}");
                (RESPONSE_OTHER, Vec::new())
            }
        };
        let mut results = HashMap::new();
        if response == RESPONSE_SUCCESS
            && let Ok(value) = OwnedVariant::try_from(Variant::from(uris))
        {
            results.insert("uris".to_owned(), value);
        }
        (response, results)
    }
}

#[interface(name = "org.freedesktop.impl.portal.FileChooser")]
impl FileChooser {
    #[zbus(name = "OpenFile")]
    async fn open_file(
        &self,
        _handle: ObjectPath<'_>,
        app_id: &str,
        _parent_window: &str,
        title: &str,
        options: HashMap<String, OwnedVariant>,
    ) -> fdo::Result<(u32, HashMap<String, OwnedVariant>)> {
        Ok(self.run(Method::OpenFile, app_id, title, options).await)
    }

    #[zbus(name = "SaveFile")]
    async fn save_file(
        &self,
        _handle: ObjectPath<'_>,
        app_id: &str,
        _parent_window: &str,
        title: &str,
        options: HashMap<String, OwnedVariant>,
    ) -> fdo::Result<(u32, HashMap<String, OwnedVariant>)> {
        Ok(self.run(Method::SaveFile, app_id, title, options).await)
    }

    #[zbus(name = "SaveFiles")]
    async fn save_files(
        &self,
        _handle: ObjectPath<'_>,
        app_id: &str,
        _parent_window: &str,
        title: &str,
        options: HashMap<String, OwnedVariant>,
    ) -> fdo::Result<(u32, HashMap<String, OwnedVariant>)> {
        Ok(self.run(Method::SaveFiles, app_id, title, options).await)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cancelled() -> Result<pb::CallReply, String> {
        Ok(pb::CallReply {
            id: 1,
            result: Some(call_reply::Result::FileChooser(pb::FileChooserResult {
                paths: Vec::new(),
                cancelled: true,
            })),
        })
    }

    fn chosen(paths: &[&str]) -> Result<pb::CallReply, String> {
        Ok(pb::CallReply {
            id: 1,
            result: Some(call_reply::Result::FileChooser(pb::FileChooserResult {
                paths: paths.iter().map(|p| p.to_string()).collect(),
                cancelled: false,
            })),
        })
    }

    #[test]
    fn flattens_glob_and_mime_filters_in_order() {
        let filters = vec![
            ("Images".to_owned(), vec![(0, "*.png".to_owned()), (1, "image/jpeg".to_owned())]),
            ("Bad".to_owned(), vec![(7, "x".to_owned()), (0, String::new())]),
        ];
        assert_eq!(parse_filters(&filters), vec!["*.png", "image/jpeg"]);
    }

    #[test]
    fn picks_the_panel_for_each_method() {
        let plain = Options::default();
        let dir = Options { directory: true, ..Default::default() };
        assert_eq!(kind_for(Method::OpenFile, &plain), Kind::Open);
        assert_eq!(kind_for(Method::OpenFile, &dir), Kind::OpenDirectory);
        assert_eq!(kind_for(Method::SaveFile, &plain), Kind::Save);
        assert_eq!(kind_for(Method::SaveFiles, &plain), Kind::OpenDirectory);
    }

    #[test]
    fn encodes_file_uris() {
        assert_eq!(file_uri("/mnt/mac/Docs/a b.txt"), "file:///mnt/mac/Docs/a%20b.txt");
        assert_eq!(file_uri("/mnt/mac/x/%é"), "file:///mnt/mac/x/%25%C3%A9");
    }

    #[test]
    fn open_returns_uris_for_chosen_paths() {
        assert_eq!(
            outcome(chosen(&["/mnt/mac/Docs/a.txt"]), Method::OpenFile, &[]),
            Outcome::Uris(vec!["file:///mnt/mac/Docs/a.txt".to_owned()])
        );
    }

    #[test]
    fn cancel_and_errors_map_to_portal_outcomes() {
        assert_eq!(outcome(cancelled(), Method::OpenFile, &[]), Outcome::Cancelled);
        assert_eq!(outcome(chosen(&[]), Method::SaveFile, &[]), Outcome::Cancelled);
        assert_eq!(outcome(Err("timeout".into()), Method::SaveFile, &[]), Outcome::Failed("timeout".into()));
    }

    #[test]
    fn save_files_appends_names_to_the_folder() {
        let names = vec!["a.txt".to_owned(), "b.txt".to_owned()];
        assert_eq!(
            outcome(chosen(&["/mnt/mac/Docs/"]), Method::SaveFiles, &names),
            Outcome::Uris(vec!["file:///mnt/mac/Docs/a.txt".to_owned(), "file:///mnt/mac/Docs/b.txt".to_owned()])
        );
    }

    #[test]
    fn options_default_when_missing_or_mistyped() {
        let mut options = HashMap::new();
        options.insert("multiple".to_owned(), OwnedVariant::try_from(Variant::from(true)).unwrap());
        options.insert("current_name".to_owned(), OwnedVariant::try_from(Variant::from(7u32)).unwrap());
        let parsed = parse_options(&options);
        assert!(parsed.multiple);
        assert!(!parsed.directory);
        assert_eq!(parsed.current_name, "");
        assert_eq!(parse_options(&HashMap::new()), Options::default());
    }
}
