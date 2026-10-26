import Foundation

/// Matching rules shared by residue scanning and orphan detection.
///
/// A macOS app can leave artifacts under several names: its bundle identifier,
/// a helper identifier (`com.foo.App.helper`), an app name (`Foo App`), an
/// executable name (`Foo`), or a team-prefixed group identifier
/// (`TEAMID.com.foo.App`). These helpers keep that logic in one place.
enum BundleMatcher {
    /// Case/diacritic-insensitive name normalization used for human-readable
    /// folder names such as `Application Support/Trae CN`.
    static func normalizeName(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        let allowed = CharacterSet.alphanumerics
        return String(folded.unicodeScalars.filter { allowed.contains($0) })
    }

    static func normalizedIdentifier(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in [".plist", ".savedstate", ".binarycookies", ".lockfile"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        if value.hasPrefix("group.") {
            value.removeFirst("group.".count)
        }
        // Group containers are commonly `TEAMID.com.vendor.App`. Team IDs are
        // ten ASCII alphanumerics followed by a dot.
        if let dot = value.firstIndex(of: ".") {
            let prefix = String(value[..<dot])
            if prefix.count == 10, prefix.allSatisfy({ $0.isLetter || $0.isNumber }),
               value[value.index(after: dot)...].contains(".") {
                value = String(value[value.index(after: dot)...])
            }
        }
        return value
    }

    static func looksLikeBundleIdentifier(_ raw: String) -> Bool {
        let value = normalizedIdentifier(raw)
        guard value.count >= 5, value.count <= 160 else { return false }
        guard value.contains("."), !value.contains(" ") else { return false }
        // Real bundle identifiers use at least two separators (`com.foo.Bar`).
        // Requiring this rejects data files such as `Cache.db` or `geoip.dat`.
        guard value.filter({ $0 == "." }).count >= 2 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        // Reject pure version strings and dotted numbers.
        return value.rangeOfCharacter(from: .letters) != nil
    }

    static func isAppleIdentifier(_ raw: String) -> Bool {
        let value = normalizedIdentifier(raw)
        return value == "apple" ||
            value.hasPrefix("com.apple.") ||
            value.hasPrefix("com.apple") ||
            value.hasPrefix("org.apple.") ||
            value.hasPrefix("apple.")
    }

    /// A small deny-list of vendor background services that are not an app and
    /// must never be presented as an orphan for one-click removal.
    static let knownBackgroundServices: Set<String> = [
        "com.microsoft.autoupdate",
        "com.microsoft.autoupdate.fba",
        "com.microsoft.autoupdate2",
        "com.microsoft.office",
        "com.microsoft.onedrive",
        "com.microsoft.onedrivestandaloneupdater",
        "com.microsoft.syncreporter",
        "com.microsoft.update.agent",
        "com.google.keystone",
        "com.google.keystone.agent",
        "com.google.keystone.daemon",
        "com.google.keystone.xpcservice",
        "com.adobe.acc",
        "com.adobe.arm",
        "com.adobe.gc",
        "com.jamf",
        "org.swift.swiftpm",
        "org.cups",
        "com.apple",
        "com.apple.dt.xcode",
        "com.openssh.sshd"
    ]

    static func isKnownBackgroundService(_ raw: String) -> Bool {
        let value = normalizedIdentifier(raw)
        if knownBackgroundServices.contains(value) { return true }
        return knownBackgroundServices.contains { value.hasPrefix($0 + ".") }
    }
}

/// Per-app matching context used by `ResidueScanner`.
struct AppMatcher: Sendable {
    let appName: String
    let nameKey: String
    let executableKey: String?
    let bundleID: String?
    let bundleToken: String?
    let appPath: String

    init(app: AppInfo) {
        self.appName = app.name
        self.nameKey = BundleMatcher.normalizeName(app.name)
        self.executableKey = app.executableName.map(BundleMatcher.normalizeName)
        self.bundleID = app.bundleID.map(BundleMatcher.normalizedIdentifier)
        if let bundleID = app.bundleID.map(BundleMatcher.normalizedIdentifier) {
            let token = bundleID.components(separatedBy: ".").last ?? ""
            self.bundleToken = token.count >= 3 ? token : nil
        } else {
            self.bundleToken = nil
        }
        self.appPath = app.url.standardizedFileURL.path
    }

    /// Does an artifact name (folder, plist stem, launchd label) belong to this app?
    func matchesIdentifier(_ raw: String) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        let candidate = BundleMatcher.normalizedIdentifier(raw)
        if candidate == bundleID { return true }
        if candidate.hasPrefix(bundleID + ".") { return true }
        if candidate.hasSuffix("." + bundleID) { return true }
        return false
    }

    func matchesName(_ raw: String) -> Bool {
        let candidate = BundleMatcher.normalizeName(raw)
        guard !candidate.isEmpty else { return false }
        if candidate == nameKey { return true }
        if let executableKey, candidate == executableKey { return true }
        // Some apps append a suffix to their support folder (e.g. `Foo Cache`).
        if nameKey.count >= 4 {
            if candidate == nameKey + "cache" || candidate == nameKey + "caches" ||
                candidate == nameKey + "logs" || candidate == nameKey + "support" {
                return true
            }
        }
        return false
    }

    /// Loose matching for one level below a vendor folder, e.g.
    /// `Application Support/@deepseek-ai/dsh-desktop` for `com.deepseek.dsh`.
    func matchesNestedName(_ raw: String) -> Bool {
        if matchesIdentifier(raw) || matchesName(raw) { return true }
        let candidate = BundleMatcher.normalizeName(raw)
        guard candidate.count >= 3 else { return false }
        if let bundleToken, bundleToken.count >= 3 {
            if candidate == bundleToken || candidate.hasPrefix(bundleToken) || bundleToken.hasPrefix(candidate) {
                return true
            }
        }
        return nameKey.count >= 4 && nameKey.hasSuffix(candidate)
    }

    /// Used for launchd plists: inspect both the file name and the properties
    /// that usually reference the owning app.
    func matchesLaunchdPlist(name: String, contents: [String: Any]) -> Bool {
        if matchesIdentifier(name) || matchesName(name) { return true }
        if let label = contents["Label"] as? String,
           matchesIdentifier(label) || matchesName(label) {
            return true
        }
        let joined = Self.strings(in: contents).joined(separator: " ")
        if joined.contains(appPath) { return true }
        if let bundleID, joined.localizedCaseInsensitiveContains(bundleID) { return true }
        return false
    }

    private static func strings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap { strings(in: $0) } }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.flatMap { strings(in: $0) }
        }
        return []
    }
}
