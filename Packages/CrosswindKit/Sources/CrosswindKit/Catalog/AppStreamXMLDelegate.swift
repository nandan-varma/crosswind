// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Streams an AppStream document and builds a `CatalogApp` per `desktop-application` component.
/// Anything carrying `xml:lang` is skipped, so only the untranslated text is kept.
final class AppStreamXMLDelegate: NSObject, XMLParserDelegate {
    /// Elements the parser acts on. Each element name is resolved once, at its start tag.
    private enum Tag {
        case component, id, name, summary, projectLicense, developerName, developer
        case keywords, keyword, categories, category, url, icon, bundle
        case contentRating, contentAttribute, custom, value
        case description, paragraph, listItem
        case releases, release, screenshots, screenshot, caption, image
        /// Inline markup inside a paragraph; its text continues the surrounding run.
        case inline
        case other
    }

    private struct Frame {
        let tag: Tag
        let attributes: [String: String]
        let localized: Bool
    }

    private static let tags: [String: Tag] = [
        "component": .component, "id": .id, "name": .name, "summary": .summary,
        "project_license": .projectLicense, "developer_name": .developerName, "developer": .developer,
        "keywords": .keywords, "keyword": .keyword, "categories": .categories, "category": .category,
        "url": .url, "icon": .icon, "bundle": .bundle,
        "content_rating": .contentRating, "content_attribute": .contentAttribute,
        "custom": .custom, "value": .value,
        "description": .description, "p": .paragraph, "li": .listItem,
        "releases": .releases, "release": .release,
        "screenshots": .screenshots, "screenshot": .screenshot, "caption": .caption, "image": .image,
        "em": .inline, "code": .inline, "b": .inline, "i": .inline, "span": .inline, "u": .inline,
    ]

    private(set) var apps: [CatalogApp] = []
    private var stack: [Frame] = []
    private var localizedDepth = 0
    /// Set while inside a component whose type is not `desktop-application`.
    private var skipping = false
    private var app: CatalogApp?
    private var developerFallback: String?
    private var release: CatalogRelease?
    private var screenshot: CatalogScreenshot?
    private var paragraphs: [String] = []
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        let tag = Self.tags[elementName] ?? .other
        // Text is the run since the last block-level start; inline markup keeps the run intact.
        if tag != .inline { text = "" }
        let localized = attributeDict["xml:lang"] != nil
        stack.append(Frame(tag: tag, attributes: attributeDict, localized: localized))
        if localized { localizedDepth += 1 }
        guard localizedDepth == 0 else { return }

        if tag == .component {
            if attributeDict["type"] == "desktop-application" {
                app = CatalogApp()
                developerFallback = nil
            } else {
                skipping = true
            }
            return
        }
        guard !skipping, app != nil else { return }

        switch tag {
        case .release:
            release = CatalogRelease()
            release?.version = attributeDict["version"] ?? ""
            release?.type = attributeDict["type"]
            release?.date = attributeDict["timestamp"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        case .screenshot:
            screenshot = CatalogScreenshot()
            screenshot?.isDefault = attributeDict["type"] == "default"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard localizedDepth == 0, !skipping, app != nil else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard let frame = stack.popLast() else { return }
        if frame.localized {
            localizedDepth -= 1
            return
        }
        guard localizedDepth == 0 else { return }

        if frame.tag == .component {
            if var finished = app {
                finished.developerName = finished.developerName ?? developerFallback
                apps.append(finished)
            }
            app = nil
            skipping = false
            return
        }
        guard !skipping, app != nil else { return }

        let parent = stack.last?.tag
        switch (frame.tag, parent) {
        case (.id, .component): app?.id = collapsed()
        case (.name, .component): app?.name = collapsed()
        case (.name, .developer): developerFallback = collapsed()
        case (.summary, .component): app?.summary = collapsed()
        case (.projectLicense, .component): app?.projectLicense = collapsed()
        case (.developerName, .component): app?.developerName = collapsed()
        case (.keyword, .keywords): app?.keywords.append(collapsed())
        case (.category, .categories): app?.categories.append(collapsed())
        case (.url, .component): assignURL(collapsed(), type: frame.attributes["type"])
        case (.icon, .component) where frame.attributes["type"] == "remote":
            appendIcon(collapsed(), attributes: frame.attributes)
        case (.bundle, .component): app?.bundle = Self.parseBundle(collapsed())
        case (.contentAttribute, .contentRating):
            app?.contentRating[frame.attributes["id"] ?? ""] = collapsed()
        case (.value, .custom) where frame.attributes["key"] == "flathub::verification::verified":
            app?.isVerified = collapsed() == "true"
        case (.paragraph, _): flushParagraph(prefix: "")
        case (.listItem, _): flushParagraph(prefix: "• ")
        default: closeBlock(frame, parent: parent)
        }
    }

    /// Closes the elements that group paragraphs, releases and screenshots.
    private func closeBlock(_ frame: Frame, parent: Tag?) {
        switch (frame.tag, parent) {
        case (.description, .component):
            app?.description = paragraphs.joined(separator: "\n\n")
            paragraphs = []
        case (.description, .release):
            release?.description = paragraphs.joined(separator: "\n\n")
            paragraphs = []
        case (.release, .releases):
            if let release { app?.releases.append(release) }
            release = nil
        case (.caption, .screenshot): screenshot?.caption = collapsed()
        case (.image, .screenshot): appendImage(collapsed(), attributes: frame.attributes)
        case (.screenshot, .screenshots):
            if let screenshot { app?.screenshots.append(screenshot) }
            screenshot = nil
        default:
            break
        }
    }

    /// Whitespace-normalized text of the element that just closed. Only the cases that need text call this.
    private func collapsed() -> String {
        Self.collapse(text)
    }

    /// Paragraph and list-item text is flushed at its closing tag so inline markup stays in place.
    private func flushParagraph(prefix: String) {
        let value = collapsed()
        text = ""
        if !value.isEmpty { paragraphs.append(prefix + value) }
    }

    private func assignURL(_ value: String, type: String?) {
        guard let url = URL(string: value) else { return }
        switch type {
        case "homepage": app?.homepage = url
        case "bugtracker": app?.bugtracker = url
        case "donation": app?.donation = url
        case "help": app?.help = url
        default: break
        }
    }

    private func appendIcon(_ value: String, attributes: [String: String]) {
        guard let url = URL(string: value) else { return }
        var icon = CatalogIcon(url: url)
        icon.width = Int(attributes["width"] ?? "") ?? 0
        icon.height = Int(attributes["height"] ?? "") ?? 0
        icon.scale = Int(attributes["scale"] ?? "") ?? 1
        app?.icons.append(icon)
    }

    private func appendImage(_ value: String, attributes: [String: String]) {
        guard let url = URL(string: value) else { return }
        let kind = CatalogImage.Kind(rawValue: attributes["type"] ?? "") ?? .source
        var image = CatalogImage(kind: kind, url: url)
        image.width = Int(attributes["width"] ?? "") ?? 0
        image.height = Int(attributes["height"] ?? "") ?? 0
        screenshot?.images.append(image)
    }

    /// `app/org.example.App/x86_64/stable`
    private static func parseBundle(_ value: String) -> CatalogBundle? {
        let parts = value.split(separator: "/")
        guard parts.count == 4 else { return nil }
        return CatalogBundle(arch: String(parts[2]), branch: String(parts[3]))
    }

    /// Trims and folds ASCII whitespace runs to one space. Multi-byte UTF-8 sequences pass through untouched.
    private static func collapse(_ value: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        var pendingSpace = false
        for byte in value.utf8 {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                pendingSpace = !bytes.isEmpty
            } else {
                if pendingSpace { bytes.append(0x20) }
                pendingSpace = false
                bytes.append(byte)
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}
