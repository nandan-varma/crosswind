// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// A desktop application from the Flathub AppStream catalog.
public struct CatalogApp: Sendable, Hashable, Identifiable {
    /// Flatpak application ID, e.g. `org.darktable.Darktable`.
    public var id = ""
    public var name = ""
    public var summary = ""
    /// Plain text. Paragraphs are separated by a blank line; list items are prefixed with "• ".
    public var description = ""
    public var categories: [String] = []
    public var keywords: [String] = []
    public var developerName: String?
    public var projectLicense: String?
    public var homepage: URL?
    public var bugtracker: URL?
    public var donation: URL?
    public var help: URL?
    /// Remote icons only; the XML's `cached` icons are bare file names with no host.
    public var icons: [CatalogIcon] = []
    public var screenshots: [CatalogScreenshot] = []
    /// In the order the catalog lists them (newest first).
    public var releases: [CatalogRelease] = []
    /// OARS attribute ID to level, e.g. `["violence-realistic": "mild"]`. Empty when unrated.
    public var contentRating: [String: String] = [:]
    /// True when Flathub has verified the app's publisher (`flathub::verification::verified`).
    public var isVerified = false
    public var bundle: CatalogBundle?

    public init() {}
}

public struct CatalogIcon: Sendable, Hashable {
    public var url: URL
    public var width = 0
    public var height = 0
    public var scale = 1

    public init(url: URL) {
        self.url = url
    }
}

public struct CatalogScreenshot: Sendable, Hashable {
    public var caption = ""
    public var isDefault = false
    public var images: [CatalogImage] = []

    public init() {}
}

public struct CatalogImage: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case source
        case thumbnail
    }

    public var kind: Kind
    public var url: URL
    public var width = 0
    public var height = 0

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

public struct CatalogRelease: Sendable, Hashable {
    public var version = ""
    public var date: Date?
    public var type: String?
    /// Release notes as plain text, same format as `CatalogApp.description`.
    public var description: String?

    public init() {}
}

/// The Flatpak bundle reference, e.g. `app/org.darktable.Darktable/x86_64/stable`.
public struct CatalogBundle: Sendable, Hashable {
    public var arch: String
    public var branch: String

    public init(arch: String, branch: String) {
        self.arch = arch
        self.branch = branch
    }
}

public enum AppStreamError: Error, Equatable {
    case notGzip
    case decompressionFailed
    case malformedXML(String)
}

/// Parses the Flathub AppStream catalog (`appstream.xml.gz`) into desktop applications.
public struct AppStreamParser {
    /// Parses a gzip-compressed AppStream catalog.
    public static func parse(gzipped data: Data) throws -> [CatalogApp] {
        try parse(xml: inflateGzip(data))
    }

    /// Parses an uncompressed AppStream catalog. Components other than `desktop-application` are skipped.
    public static func parse(xml data: Data) throws -> [CatalogApp] {
        let delegate = AppStreamXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw AppStreamError.malformedXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return delegate.apps
    }

    /// Strips the gzip container (RFC 1952) and inflates the raw DEFLATE payload.
    /// The gzip trailer (CRC and size) is not verified.
    static func inflateGzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
            throw AppStreamError.notGzip
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {  // FEXTRA
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        if flags & 0x08 != 0 {  // FNAME
            offset = skipZeroTerminated(bytes, from: offset)
        }
        if flags & 0x10 != 0 {  // FCOMMENT
            offset = skipZeroTerminated(bytes, from: offset)
        }
        if flags & 0x02 != 0 {  // FHCRC
            offset += 2
        }
        guard offset < bytes.count - 8 else { throw AppStreamError.notGzip }
        let payload = Data(bytes[offset..<(bytes.count - 8)])
        guard let inflated = try? (payload as NSData).decompressed(using: .zlib) as Data else {
            throw AppStreamError.decompressionFailed
        }
        return inflated
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) -> Int {
        var offset = start
        while offset < bytes.count && bytes[offset] != 0 {
            offset += 1
        }
        return offset + 1
    }
}
