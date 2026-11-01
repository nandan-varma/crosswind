// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Carbon.HIToolbox

/// An XKB layout and variant, the names the guest's xkb keymap is built from.
struct XkbLayout: Equatable {
    let layout: String
    let variant: String

    static let us = XkbLayout(layout: "us", variant: "")
}

/// Maps macOS keyboard input source IDs (checked against `TISCreateInputSourceList` on macOS 27) to XKB layouts.
/// Input methods (Kotoeri, Korean, Pinyin) and unknown sources map to US: the IME composes from US keys, and the
/// host sends the composed text, so the guest keymap only matters for keys that bypass the IME.
enum KeyboardLayoutMap {
    static func xkb(forInputSourceID id: String) -> XkbLayout { table[id] ?? .us }

    private static let table: [String: XkbLayout] = [
        "com.apple.keylayout.US": .us,
        "com.apple.keylayout.ABC": .us,
        "com.apple.keylayout.USExtended": .us,
        "com.apple.keylayout.British": XkbLayout(layout: "gb", variant: ""),
        "com.apple.keylayout.German": XkbLayout(layout: "de", variant: ""),
        "com.apple.keylayout.French": XkbLayout(layout: "fr", variant: ""),
        "com.apple.keylayout.Spanish": XkbLayout(layout: "es", variant: ""),
        "com.apple.keylayout.Spanish-ISO": XkbLayout(layout: "es", variant: ""),
        "com.apple.keylayout.Italian": XkbLayout(layout: "it", variant: ""),
        "com.apple.keylayout.Portuguese": XkbLayout(layout: "pt", variant: ""),
        "com.apple.keylayout.Dutch": XkbLayout(layout: "nl", variant: ""),
        "com.apple.keylayout.Swedish-Pro": XkbLayout(layout: "se", variant: ""),
        "com.apple.keylayout.Swedish": XkbLayout(layout: "se", variant: ""),
        "com.apple.keylayout.Norwegian": XkbLayout(layout: "no", variant: ""),
        "com.apple.keylayout.Danish": XkbLayout(layout: "dk", variant: ""),
        "com.apple.keylayout.Finnish": XkbLayout(layout: "fi", variant: ""),
        "com.apple.keylayout.SwissGerman": XkbLayout(layout: "ch", variant: ""),
        "com.apple.keylayout.SwissFrench": XkbLayout(layout: "ch", variant: "fr"),
        "com.apple.keylayout.Russian": XkbLayout(layout: "ru", variant: ""),
        "com.apple.keylayout.Ukrainian": XkbLayout(layout: "ua", variant: ""),
        "com.apple.keylayout.Polish": XkbLayout(layout: "pl", variant: ""),
        "com.apple.keylayout.Czech": XkbLayout(layout: "cz", variant: ""),
        "com.apple.keylayout.Turkish-QWERTY-PC": XkbLayout(layout: "tr", variant: ""),
        "com.apple.keylayout.Turkish-QWERTY": XkbLayout(layout: "tr", variant: ""),
        "com.apple.keylayout.Arabic": XkbLayout(layout: "ara", variant: ""),
        "com.apple.keylayout.Hebrew": XkbLayout(layout: "il", variant: ""),
        "com.apple.keylayout.Hebrew-QWERTY": XkbLayout(layout: "il", variant: ""),
        "com.apple.keylayout.Greek": XkbLayout(layout: "gr", variant: ""),
        "com.apple.keylayout.Dvorak": XkbLayout(layout: "us", variant: "dvorak"),
        "com.apple.keylayout.Colemak": XkbLayout(layout: "us", variant: "colemak"),
    ]

    /// The ID of the keyboard input source selected right now, or nil if macOS reports none.
    static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// Tracks the selected macOS keyboard layout and reports changes, so each guest can rebuild its keymap.
@MainActor
final class KeyboardLayoutObserver {
    private(set) var current: XkbLayout
    private let onChange: (XkbLayout) -> Void
    /// Written once in `init`; `deinit` (nonisolated) reads it to unregister.
    private nonisolated(unsafe) var token: NSObjectProtocol?

    init(onChange: @escaping (XkbLayout) -> Void) {
        self.onChange = onChange
        current = Self.detect()
        token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
    }

    private static func detect() -> XkbLayout {
        KeyboardLayoutMap.currentInputSourceID().map(KeyboardLayoutMap.xkb(forInputSourceID:)) ?? .us
    }

    private func refresh() {
        let layout = Self.detect()
        guard layout != current else { return }
        current = layout
        onChange(layout)
    }
}
