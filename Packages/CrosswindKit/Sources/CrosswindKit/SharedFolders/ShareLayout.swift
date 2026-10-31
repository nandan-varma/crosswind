// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Virtualization

/// The virtiofs share the guest mounts at `/mnt/mac`: one directory per granted folder (read-only when the grant
/// says so), plus the staging directory. Nothing else of the Mac is exported.
public enum ShareLayout {
    public static func directories(for folders: SharedFolders, staging: URL = Staging.root) -> [String: VZSharedDirectory]
    {
        var directories: [String: VZSharedDirectory] = [:]
        for folder in folders.folders {
            directories[folder.name] = VZSharedDirectory(url: URL(fileURLWithPath: folder.path), readOnly: folder.readOnly)
        }
        directories[Staging.shareName] = VZSharedDirectory(url: staging, readOnly: false)
        return directories
    }

    /// The device share for `folders`; `VZVirtioFileSystemDevice.share` takes it, also while the VM runs.
    public static func share(for folders: SharedFolders, staging: URL = Staging.root) -> VZMultipleDirectoryShare {
        VZMultipleDirectoryShare(directories: directories(for: folders, staging: staging))
    }
}
