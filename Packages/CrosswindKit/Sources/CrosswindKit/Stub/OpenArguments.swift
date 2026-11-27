// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// What Finder or a link hands an app's stub, turned into the command line of the Linux app: files become guest
/// paths and other URLs (tg://, magnet:) are passed through as they are.
public enum OpenArguments {
    /// - Parameter guestPath: maps a Mac file to its path in the guest (a shared folder, or the staging copy);
    ///   nil drops the file.
    public static func make(from urls: [URL], guestPath: (URL) -> String?) -> [String] {
        urls.compactMap { url in url.isFileURL ? guestPath(url) : url.absoluteString }
    }
}
