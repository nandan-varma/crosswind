// SPDX-License-Identifier: AGPL-3.0-or-later
//! Limits on data that crosses a trust boundary: host requests (trusted, but still validated so a bad message
//! cannot crash the compositor) and guest app requests (untrusted, relayed to the Mac). The host enforces the
//! same numbers again (`DisplayLimits` in CrosswindKit); see docs/security.md.

/// Largest surface side and pixel count the host accepts for a window.
pub const MAX_SIDE: u32 = 16_384;
pub const MAX_PIXELS: u64 = 64 << 20;
/// `scale_120` range the host accepts (0.5x to 8x).
pub const SCALE_120_MIN: u32 = 60;
pub const SCALE_120_MAX: u32 = 960;

pub const MAX_TITLE: usize = 1024;
pub const MAX_IDENTIFIER: usize = 256;
pub const MAX_LOG_TEXT: usize = 4096;
pub const MAX_ARGS: usize = 64;
pub const MAX_ARG_BYTES: usize = 4096;
pub const MAX_MIMES: usize = 16;
pub const MAX_MIME: usize = 64;
pub const MAX_TIMEZONE: usize = 64;
pub const MAX_NOTIFY_TITLE: usize = 256;
pub const MAX_NOTIFY_BODY: usize = 2048;
pub const MAX_NOTIFY_ICON: usize = 1 << 20;
pub const MAX_FILTERS: usize = 64;
pub const MAX_PATTERN: usize = 256;
pub const MAX_FIELD: usize = 256;
pub const MAX_FILES: usize = 256;

/// Whether a surface of `width` x `height` physical pixels at `scale_120` is one the host will accept.
pub fn surface_ok(width: u32, height: u32, scale_120: u32) -> bool {
    width > 0
        && height > 0
        && width <= MAX_SIDE
        && height <= MAX_SIDE
        && (width as u64) * (height as u64) <= MAX_PIXELS
        && (SCALE_120_MIN..=SCALE_120_MAX).contains(&scale_120)
}

/// Truncates `s` to at most `max` bytes, on a character boundary.
pub fn truncate(s: &str, max: usize) -> &str {
    if s.len() <= max {
        return s;
    }
    let mut end = max;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

/// Free text from an app or the host: control characters, line and paragraph separators and bidi
/// overrides/isolates are removed, then the result is cut to `max` bytes.
pub fn clean(s: &str, max: usize) -> String {
    let kept: String = s.chars().filter(|c| !is_stripped(*c)).collect();
    truncate(&kept, max).to_owned()
}

fn is_stripped(c: char) -> bool {
    c.is_control()
        || matches!(c,
            '\u{061C}' | '\u{200E}' | '\u{200F}' | '\u{2028}' | '\u{2029}'
            | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{FEFF}')
}

/// A Flatpak application id: reverse-DNS characters only, and never a leading `-` (which `flatpak` would read as
/// an option).
pub fn valid_app_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= MAX_IDENTIFIER
        && !id.starts_with('-')
        && id.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

/// Only web links and mail may be opened on the Mac on behalf of a guest app.
pub fn allowed_url_scheme(url: &str) -> bool {
    match url.split_once(':') {
        Some((scheme, _)) => matches!(scheme.to_ascii_lowercase().as_str(), "http" | "https" | "mailto"),
        None => false,
    }
}

/// A host finite coordinate. NaN and infinities are dropped rather than handed to the input stack.
pub fn finite(v: f64) -> bool {
    v.is_finite()
}

/// Deterministic generator for fuzz-style tests (xorshift64).
#[cfg(test)]
pub fn xorshift(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    x
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn surface_limits_have_edges() {
        assert!(surface_ok(MAX_SIDE, 4096, 120));
        assert!(!surface_ok(MAX_SIDE, 4097, 120));
        assert!(!surface_ok(0, 1, 120));
        assert!(surface_ok(1, 1, SCALE_120_MIN));
        assert!(!surface_ok(1, 1, SCALE_120_MIN - 1));
        assert!(!surface_ok(1, 1, SCALE_120_MAX + 1));
        assert!(!surface_ok(u32::MAX, u32::MAX, u32::MAX));
    }

    #[test]
    fn truncate_respects_char_boundaries() {
        assert_eq!(truncate("aéé", 3), "aé");
        assert_eq!(truncate("abc", 10), "abc");
        assert_eq!(truncate("", 0), "");
    }

    #[test]
    fn clean_drops_controls_and_bidi() {
        assert_eq!(clean("Save\u{202E}txt\nFake\u{0007}", 1024), "SavetxtFake");
        assert_eq!(clean(&"x".repeat(5000), 1024).len(), 1024);
    }

    #[test]
    fn app_ids_must_be_reverse_dns() {
        assert!(valid_app_id("org.gnome.Calculator"));
        assert!(valid_app_id("org.example.my-app_2"));
        assert!(!valid_app_id(""));
        assert!(!valid_app_id("--command=sh"));
        assert!(!valid_app_id("org.example/../x"));
        assert!(!valid_app_id("org.example app"));
        assert!(!valid_app_id(&"a".repeat(MAX_IDENTIFIER + 1)));
    }

    #[test]
    fn url_schemes_are_an_allowlist() {
        assert!(allowed_url_scheme("https://example.com"));
        assert!(allowed_url_scheme("HTTP://example.com"));
        assert!(allowed_url_scheme("mailto:me@example.com"));
        assert!(!allowed_url_scheme("file:///etc/passwd"));
        assert!(!allowed_url_scheme("smb://host/share"));
        assert!(!allowed_url_scheme("javascript:alert(1)"));
        assert!(!allowed_url_scheme("no-colon"));
    }
}
