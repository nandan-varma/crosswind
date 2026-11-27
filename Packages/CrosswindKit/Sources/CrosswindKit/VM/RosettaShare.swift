// SPDX-License-Identifier: AGPL-3.0-or-later
import Virtualization

/// Rosetta for Linux: the translator that lets the arm64 guest run x86_64 programs. The VM exports it as a virtiofs
/// share; the guest mounts it and registers it as the handler for x86_64 ELF binaries (`crosswind-rosetta` service).
enum RosettaShare {
    /// The virtiofs tag the guest mounts.
    static let tag = "rosetta"

    /// The device to add to the VM, or nil when Rosetta is not installed on this Mac or the user turned it off.
    static func device() -> VZVirtioFileSystemDeviceConfiguration? {
        guard Preferences.rosettaEnabled, VZLinuxRosettaDirectoryShare.availability == .installed else { return nil }
        guard let share = try? VZLinuxRosettaDirectoryShare() else { return nil }
        let device = VZVirtioFileSystemDeviceConfiguration(tag: tag)
        device.share = share
        return device
    }
}
