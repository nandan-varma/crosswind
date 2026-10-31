// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Removes personal and network identifiers from text before it leaves the Mac in a diagnostic bundle.
///
/// Order matters: URL queries and bearer tokens go first so that later rules do not split them.
/// Versions (`51.1`, `26.1.0`), short commit hashes and times (`12:34:56`) are left alone.
public struct Redactor: Sendable {
    /// The guest's virtio NAT subnet. Addresses in it are kept: they identify no one.
    public static let guestNetworkPrefix = "192.168.64."

    public let homeDirectory: String
    public let userName: String

    public init(homeDirectory: String = NSHomeDirectory(), userName: String = NSUserName()) {
        self.homeDirectory = homeDirectory
        self.userName = userName
    }

    public func redact(_ text: String) -> String {
        var result = Self.substitute(text, pattern: #"https?://[^\s<>"']+"#) { token in
            guard let query = token.firstIndex(of: "?") else { return nil }
            return String(token[..<query]) + "?<redacted>"
        }
        result = Self.substitute(result, pattern: #"(?i)Bearer\s+[A-Za-z0-9._~+\-/=]+"#) { _ in "Bearer <redacted>" }
        result = Self.substitute(result, pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}"#) {
            _ in "<email>"
        }
        result = Self.substitute(result, pattern: #"\b[0-9A-Fa-f]{2}(?:[:\-][0-9A-Fa-f]{2}){5}\b"#) { _ in "<mac>" }
        result = Self.substitute(result, pattern: #"(?<![0-9A-Za-z.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9A-Za-z]|\.\d)"#) {
            token in
            guard Self.isIPv4(token), !token.hasPrefix(Self.guestNetworkPrefix) else { return nil }
            return "<ipv4>"
        }
        result = Self.substitute(result, pattern: #"(?<![0-9A-Za-z:])[0-9A-Fa-f:]{2,39}(?![0-9A-Za-z:])"#) { token in
            Self.isIPv6(token) ? "<ipv6>" : nil
        }
        result = Self.substitute(result, pattern: #"[A-Za-z0-9+_\-]{32,}={0,2}"#) { token in
            let hasDigit = token.contains { $0.isNumber }
            let hasLetter = token.contains { $0.isLetter }
            return hasDigit && hasLetter ? "<token>" : nil
        }
        if !homeDirectory.isEmpty, homeDirectory != "/" {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }
        if !userName.isEmpty {
            result = Self.substitute(result, pattern: "\\b\(NSRegularExpression.escapedPattern(for: userName))\\b") {
                _ in "<user>"
            }
        }
        return result
    }

    /// Replaces every match of `pattern`; `transform` returns the replacement, or nil to keep the match.
    static func substitute(_ text: String, pattern: String, _ transform: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard let replacement = transform(source.substring(with: match.range)) else { continue }
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            result += replacement
            last = match.range.location + match.range.length
        }
        return result + source.substring(from: last)
    }

    static func isIPv4(_ token: String) -> Bool {
        let octets = token.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { Int($0).map { $0 <= 255 } ?? false }
    }

    /// Accepts `::`-compressed forms and full eight-group forms. Clock times such as `12:34:56` are rejected.
    static func isIPv6(_ token: String) -> Bool {
        let isHexGroup: (Substring) -> Bool = { $0.count <= 4 && $0.allSatisfy { $0.isHexDigit } }
        if token.contains("::") {
            guard token.components(separatedBy: "::").count == 2 else { return false }
            let groups = token.split(separator: ":").filter { !$0.isEmpty }
            return token.filter({ $0 == ":" }).count >= 2 && groups.count <= 7 && groups.allSatisfy(isHexGroup)
        }
        let groups = token.split(separator: ":", omittingEmptySubsequences: false)
        return groups.count == 8 && groups.allSatisfy(isHexGroup)
    }
}
