// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The Flatpak permission lists of one app, as the guest reports them. Pure value logic: the grouping, the labels
/// and the override delta live here so they can be tested without a guest.
public struct AppPermissions: Sendable, Equatable {
    public var sockets: [String]
    public var devices: [String]
    public var shared: [String]
    public var filesystems: [String]
    public var features: [String]

    public init(
        sockets: [String] = [], devices: [String] = [], shared: [String] = [], filesystems: [String] = [],
        features: [String] = []
    ) {
        self.sockets = sockets
        self.devices = devices
        self.shared = shared
        self.filesystems = filesystems
        self.features = features
    }

    public init(_ proto: Crosswind_Control_Permissions) {
        self.init(
            sockets: proto.sockets, devices: proto.devices, shared: proto.shared, filesystems: proto.filesystems,
            features: proto.features)
    }

    /// The permissions to send to the guest. The manifest defaults are not part of a request.
    public var proto: Crosswind_Control_Permissions {
        Crosswind_Control_Permissions.with {
            $0.sockets = sockets
            $0.devices = devices
            $0.shared = shared
            $0.filesystems = filesystems
            $0.features = features
        }
    }

    // MARK: Toggles

    public func isOn(_ option: PermissionOption) -> Bool {
        values(in: option.field).contains(option.value)
    }

    public mutating func set(_ option: PermissionOption, on: Bool) {
        var list = values(in: option.field)
        list.removeAll { $0 == option.value }
        if on { list.append(option.value) }
        setValues(list, in: option.field)
    }

    private func values(in field: PermissionField) -> [String] {
        switch field {
        case .sockets: sockets
        case .devices: devices
        case .shared: shared
        case .features: features
        case .filesystems: filesystems
        }
    }

    private mutating func setValues(_ list: [String], in field: PermissionField) {
        switch field {
        case .sockets: sockets = list
        case .devices: devices = list
        case .shared: shared = list
        case .features: features = list
        case .filesystems: filesystems = list
        }
    }

    // MARK: Filesystems

    /// The access entries, in the order the guest reports them.
    public var fileAccess: [FilesystemAccess] {
        filesystems.map(FilesystemAccess.init(parsing:))
    }

    /// The entry for `path` (for example `xdg-download`), whatever its mode.
    public func access(to path: String) -> FilesystemAccess? {
        fileAccess.first { $0.path == path }
    }

    /// Replaces the entry for the same path, or appends it.
    public mutating func setAccess(_ access: FilesystemAccess) {
        let entry = access.entry
        if let index = filesystems.firstIndex(where: { FilesystemAccess(parsing: $0).path == access.path }) {
            filesystems[index] = entry
        } else {
            filesystems.append(entry)
        }
    }

    public mutating func removeAccess(to path: String) {
        filesystems.removeAll { FilesystemAccess(parsing: $0).path == path }
    }

    // MARK: Overrides

    /// Whether `option` differs from the manifest default.
    public func isChanged(_ option: PermissionOption, from defaults: AppPermissions) -> Bool {
        isOn(option) != defaults.isOn(option)
    }

    /// Whether the entry for `path` differs from the manifest default (added, removed or another mode).
    public func isChanged(path: String, from defaults: AppPermissions) -> Bool {
        access(to: path)?.entry != defaults.access(to: path)?.entry
    }

    /// Number of toggles and paths that differ from the manifest defaults. Zero means no override.
    public func changeCount(from defaults: AppPermissions) -> Int {
        let toggles = PermissionCatalog.options(for: self, defaults: defaults).filter {
            isChanged($0, from: defaults)
        }
        let paths = Set(fileAccess.map(\.path)).union(defaults.fileAccess.map(\.path))
        let files = paths.filter { isChanged(path: $0, from: defaults) }
        return toggles.count + files.count
    }
}

/// Which `Crosswind_Control_Permissions` list an option lives in.
public enum PermissionField: Sendable, Hashable {
    case sockets, devices, shared, features, filesystems
}

/// Permissions shown as a switch. Plain-language copy lives here, next to the Flatpak value it stands for.
public struct PermissionOption: Identifiable, Sendable, Hashable {
    public enum Group: String, CaseIterable, Sendable {
        case network, windowing, sound, devices, files, features, other
    }

    public let field: PermissionField
    public let value: String
    public let group: Group
    public let title: LocalizedStringResource
    public let detail: LocalizedStringResource
    /// SF Symbol name.
    public let symbol: String
    /// Access that reaches far beyond the app (the whole system, the home folder, every device).
    public let isBroad: Bool

    public var id: String { "\(field):\(value)" }

    public init(
        field: PermissionField, value: String, group: Group, title: LocalizedStringResource,
        detail: LocalizedStringResource, symbol: String, isBroad: Bool = false
    ) {
        self.field = field
        self.value = value
        self.group = group
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.isBroad = isBroad
    }

    public static func == (lhs: PermissionOption, rhs: PermissionOption) -> Bool { lhs.id == rhs.id }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Folders and files an app may reach, with their mode.
public struct FilesystemAccess: Sendable, Hashable {
    public enum Mode: String, CaseIterable, Sendable {
        /// No suffix: read and write.
        case readWrite
        /// `:ro`
        case readOnly
        /// `:create`: read and write, and create the folder if it is missing.
        case create

        public var title: LocalizedStringResource {
            switch self {
            case .readWrite: "Read and Write"
            case .readOnly: "Read Only"
            case .create: "Create and Write"
            }
        }

        var suffix: String {
            switch self {
            case .readWrite: ""
            case .readOnly: ":ro"
            case .create: ":create"
            }
        }
    }

    public var path: String
    public var mode: Mode

    public init(path: String, mode: Mode = .readWrite) {
        self.path = path
        self.mode = mode
    }

    /// Parses a Flatpak filesystem entry such as `xdg-download:ro`. Only a trailing `:ro`, `:rw` or `:create` is
    /// a mode; any other colon belongs to the path.
    public init(parsing entry: String) {
        let suffixed: [(Mode, String)] = [(.readOnly, ":ro"), (.create, ":create"), (.readWrite, ":rw")]
        if let match = suffixed.first(where: { entry.hasSuffix($0.1) }) {
            self.init(path: String(entry.dropLast(match.1.count)), mode: match.0)
        } else {
            self.init(path: entry, mode: .readWrite)
        }
    }

    /// The Flatpak entry, for example `xdg-download:ro`.
    public var entry: String { path + mode.suffix }

    /// Whether `path` can be added as a custom folder. Paths are Flatpak paths: absolute, `~/` or `xdg-*`. Entries
    /// are separated by `;` in the override file, so that character and a leading `!` (removal) are refused.
    public static func isValidCustomPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(";"), !trimmed.contains("\n"), !trimmed.hasPrefix("!") else {
            return false
        }
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("xdg-")
    }
}

/// A common folder shown as a row in Files.
public struct FilesystemPreset: Identifiable, Sendable {
    public let path: String
    public let title: LocalizedStringResource
    public let detail: LocalizedStringResource
    public let symbol: String
    public let isBroad: Bool

    public var id: String { path }
}

/// The catalog of permissions Crosswind shows, grouped for the UI.
public enum PermissionCatalog {
    public static let options: [PermissionOption] = [
        PermissionOption(
            field: .shared, value: "network", group: .network, title: "Network Access",
            detail: "Connect to the internet and to devices on your local network.", symbol: "network"),
        PermissionOption(
            field: .sockets, value: "x11", group: .windowing, title: "X11 Windows",
            detail: "Show windows through the X11 protocol. Needed by apps without Wayland support.",
            symbol: "macwindow"),
        PermissionOption(
            field: .sockets, value: "wayland", group: .windowing, title: "Wayland Windows",
            detail: "Show windows through the native Wayland protocol.", symbol: "rectangle.on.rectangle"),
        PermissionOption(
            field: .sockets, value: "fallback-x11", group: .windowing, title: "X11 Fallback",
            detail: "Use X11 only when Wayland is not available.", symbol: "rectangle.stack"),
        PermissionOption(
            field: .shared, value: "ipc", group: .windowing, title: "Shared Memory",
            detail: "Share memory and inter-process communication with other programs in the Linux environment.",
            symbol: "memorychip"),
        PermissionOption(
            field: .sockets, value: "pulseaudio", group: .sound, title: "Audio Playback and Recording",
            detail: "Play and record sound through PulseAudio or PipeWire.", symbol: "speaker.wave.2"),
        PermissionOption(
            field: .devices, value: "dri", group: .devices, title: "3D Graphics Acceleration",
            detail: "Use the graphics processor for OpenGL and Vulkan.", symbol: "cube"),
        PermissionOption(
            field: .devices, value: "kvm", group: .devices, title: "Virtualization",
            detail: "Run virtual machines through the KVM device.", symbol: "server.rack"),
        PermissionOption(
            field: .devices, value: "all", group: .devices, title: "All Devices",
            detail: "Access every device, including USB, serial and camera devices. Only for apps you trust.",
            symbol: "externaldrive.connected.to.line.below", isBroad: true),
        PermissionOption(
            field: .features, value: "bluetooth", group: .features, title: "Bluetooth",
            detail: "Discover and connect to Bluetooth devices.", symbol: "dot.radiowaves.left.and.right"),
        PermissionOption(
            field: .features, value: "devel", group: .features, title: "Developer Tools",
            detail: "Trace and debug other programs, as developer tools need.", symbol: "hammer"),
    ]

    public static let filesystemPresets: [FilesystemPreset] = [
        FilesystemPreset(
            path: "xdg-documents", title: "Documents", detail: "Your Documents folder.", symbol: "doc.text",
            isBroad: false),
        FilesystemPreset(
            path: "xdg-download", title: "Downloads", detail: "Your Downloads folder.", symbol: "arrow.down.circle",
            isBroad: false),
        FilesystemPreset(
            path: "xdg-pictures", title: "Pictures", detail: "Your Pictures folder.", symbol: "photo",
            isBroad: false),
        FilesystemPreset(
            path: "xdg-music", title: "Music", detail: "Your Music folder.", symbol: "music.note", isBroad: false),
        FilesystemPreset(
            path: "xdg-videos", title: "Movies", detail: "Your Movies folder.", symbol: "film", isBroad: false),
        FilesystemPreset(
            path: "xdg-desktop", title: "Desktop", detail: "Your Desktop folder.", symbol: "menubar.dock.rectangle",
            isBroad: false),
        FilesystemPreset(
            path: "home", title: "Home Folder", detail: "Your whole Linux home folder, including hidden files.",
            symbol: "house", isBroad: true),
        FilesystemPreset(
            path: "host", title: "Entire System", detail: "Every file in the Linux environment.",
            symbol: "internaldrive", isBroad: true),
    ]

    /// The option for a Flatpak value, when Crosswind shows it.
    public static func option(field: PermissionField, value: String) -> PermissionOption? {
        options.first { $0.field == field && $0.value == value }
    }

    /// Options of `permissions` that the catalog does not know, such as entries set by a manifest or by hand in
    /// the override file. Shown under "Other" so that nothing is hidden. Defaults are included so that removed
    /// unknown entries can be seen too.
    public static func options(for permissions: AppPermissions, defaults: AppPermissions) -> [PermissionOption] {
        var result = options
        for field in [PermissionField.sockets, .devices, .shared, .features] {
            let values = Set(permissionsValues(permissions, field) + permissionsValues(defaults, field))
            for value in values.sorted() where option(field: field, value: value) == nil {
                result.append(
                    PermissionOption(
                        field: field, value: value, group: .other,
                        title: LocalizedStringResource(stringLiteral: value),
                        detail: "Entry not listed by Crosswind.", symbol: "questionmark.circle"))
            }
        }
        return result
    }

    /// Options grouped for the UI, in display order. Empty groups are dropped.
    public static func grouped(
        _ options: [PermissionOption]
    ) -> [(group: PermissionOption.Group, options: [PermissionOption])] {
        PermissionOption.Group.allCases.compactMap { group in
            let members = options.filter { $0.group == group }
            return members.isEmpty ? nil : (group, members)
        }
    }

    private static func permissionsValues(_ permissions: AppPermissions, _ field: PermissionField) -> [String] {
        switch field {
        case .sockets: permissions.sockets
        case .devices: permissions.devices
        case .shared: permissions.shared
        case .features: permissions.features
        case .filesystems: permissions.filesystems
        }
    }
}

/// The effective permissions of an app and, when the guest reports it, the manifest defaults they are compared
/// against. `defaults` is nil for a guest that cannot tell defaults from overrides.
public struct PermissionsReport: Sendable, Equatable {
    public var effective: AppPermissions
    public var defaults: AppPermissions?

    public init(effective: AppPermissions, defaults: AppPermissions?) {
        self.effective = effective
        self.defaults = defaults
    }

    public init(_ proto: Crosswind_Control_Permissions) {
        effective = AppPermissions(proto)
        defaults = proto.hasDefaults ? AppPermissions(proto.defaults) : nil
    }
}
