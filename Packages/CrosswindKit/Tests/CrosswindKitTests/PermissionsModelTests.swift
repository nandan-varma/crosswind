// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import CrosswindKit

@Suite("FilesystemAccess")
struct FilesystemAccessTests {
    @Test("parses the mode suffix", arguments: [
        ("xdg-download:ro", "xdg-download", FilesystemAccess.Mode.readOnly),
        ("xdg-download:rw", "xdg-download", .readWrite),
        ("xdg-download:create", "xdg-download", .create),
        ("xdg-download", "xdg-download", .readWrite),
        ("~/Projects:ro", "~/Projects", .readOnly),
        ("/srv/data:create", "/srv/data", .create),
        ("/srv/a:b", "/srv/a:b", .readWrite),
    ])
    func parsesEntries(entry: String, path: String, mode: FilesystemAccess.Mode) {
        let access = FilesystemAccess(parsing: entry)
        #expect(access.path == path)
        #expect(access.mode == mode)
    }

    @Test("serializes back to the Flatpak entry", arguments: [
        ("xdg-download:ro", "xdg-download:ro"),
        ("xdg-documents", "xdg-documents"),
        ("~/Projects:create", "~/Projects:create"),
    ])
    func roundTrips(entry: String, expected: String) {
        #expect(FilesystemAccess(parsing: entry).entry == expected)
    }

    @Test("accepts Flatpak paths and refuses malformed ones", arguments: [
        ("/srv/data", true), ("~/Projects", true), ("xdg-music", true),
        ("", false), ("   ", false), ("Projects", false), ("/a;/b", false), ("!/srv", false),
    ])
    func validatesCustomPaths(path: String, valid: Bool) {
        #expect(FilesystemAccess.isValidCustomPath(path) == valid)
    }
}

@Suite("AppPermissions")
struct AppPermissionsTests {
    private let network = PermissionCatalog.options.first { $0.value == "network" }!
    private let wayland = PermissionCatalog.options.first { $0.value == "wayland" }!

    @Test("toggles set and clear the value in its list")
    func togglesEditTheRightList() {
        var permissions = AppPermissions()
        permissions.set(network, on: true)
        permissions.set(wayland, on: true)
        #expect(permissions.shared == ["network"])
        #expect(permissions.sockets == ["wayland"])
        #expect(permissions.isOn(network))

        permissions.set(network, on: false)
        #expect(permissions.shared.isEmpty)
        #expect(!permissions.isOn(network))
    }

    @Test("groups keep catalog order and drop empty groups")
    func grouping() {
        let groups = PermissionCatalog.grouped(PermissionCatalog.options)
        #expect(groups.map(\.group) == [.network, .windowing, .sound, .devices, .features])
        #expect(groups.first { $0.group == .windowing }?.options.map(\.value) == ["x11", "wayland", "fallback-x11", "ipc"])
        #expect(PermissionCatalog.grouped([network]).map(\.group) == [.network])
    }

    @Test("unknown entries are listed under Other, once, with their raw value")
    func unknownEntries() {
        let permissions = AppPermissions(sockets: ["x11", "cups"], devices: ["usb"])
        let other = PermissionCatalog.options(for: permissions, defaults: AppPermissions(features: ["gps"]))
            .filter { $0.group == .other }
        #expect(other.map(\.id) == ["sockets:cups", "devices:usb", "features:gps"])
    }

    @Test("the delta against defaults counts changed toggles and changed paths")
    func changeCount() {
        let defaults = AppPermissions(
            sockets: ["x11"], shared: ["network"], filesystems: ["xdg-download", "xdg-documents:ro"])
        var permissions = defaults
        #expect(permissions.changeCount(from: defaults) == 0)

        permissions.set(network, on: false)  // removed toggle
        permissions.set(wayland, on: true)  // added toggle
        permissions.setAccess(FilesystemAccess(path: "xdg-documents", mode: .readWrite))  // mode changed
        permissions.setAccess(FilesystemAccess(path: "~/Projects", mode: .create))  // added path
        #expect(permissions.changeCount(from: defaults) == 4)
        #expect(permissions.isChanged(network, from: defaults))
        #expect(!permissions.isChanged(PermissionCatalog.options.first { $0.value == "x11" }!, from: defaults))
        #expect(permissions.isChanged(path: "xdg-documents", from: defaults))
        #expect(!permissions.isChanged(path: "xdg-download", from: defaults))
    }

    @Test("removing an access entry removes only that path")
    func removeAccess() {
        var permissions = AppPermissions(filesystems: ["xdg-download:ro", "xdg-documents"])
        permissions.removeAccess(to: "xdg-download")
        #expect(permissions.filesystems == ["xdg-documents"])
    }

    @Test("a proto round trip keeps the lists, and the report reads the defaults")
    func protoRoundTrip() {
        let overridden = Crosswind_Control_Permissions.with {
            $0.shared = ["network"]
            $0.filesystems = ["xdg-pictures:ro"]
            $0.defaults = Crosswind_Control_Permissions.with { $0.shared = ["network", "ipc"] }
        }
        let report = PermissionsReport(overridden)
        #expect(report.effective == AppPermissions(shared: ["network"], filesystems: ["xdg-pictures:ro"]))
        #expect(report.defaults == AppPermissions(shared: ["network", "ipc"]))
        #expect(AppPermissions(overridden).proto.shared == ["network"])
        #expect(!AppPermissions(overridden).proto.hasDefaults)
    }

    @Test("a guest without defaults gives no baseline")
    func missingDefaults() {
        #expect(PermissionsReport(Crosswind_Control_Permissions()).defaults == nil)
    }
}
