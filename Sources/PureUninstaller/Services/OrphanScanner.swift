import Foundation

/// Heuristic detection of leftovers whose owning app is no longer installed.
///
/// This is intentionally conservative. A group is only a *candidate*: it is
/// displayed with a confidence badge, defaults to unselected, and must be
/// reviewed in the same preview tree before anything is deleted.
enum OrphanScanner {
    struct Result {
        let groups: [OrphanGroup]
        let warnings: [String]
        let scannedArtifacts: Int
    }

    private struct RootSpec {
        let url: URL
        let category: ResidueCategory
        let inspectOneLevel: Bool
    }

    private struct Artifact {
        let url: URL
        let category: ResidueCategory
        let requiresAdmin: Bool
        let key: String
        let displayName: String
    }

    private static let installedNameAllowlistKeys: Set<String> = [
        "google", "microsoft", "adobe", "mozilla", "apple", "tencent", "bytedance",
        "jetbrains", "unity", "steam", "docker", "logitech", "openai", "oracle",
        "vmware", "parallels", "setapp", "homebrew"
    ]

    static func scan(installedApps: [AppInfo]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            scanSync(installedApps: installedApps)
        }.value
    }

    private static func scanSync(installedApps: [AppInfo]) -> Result {
        let index = InstalledIndex(apps: installedApps)
        var artifacts: [Artifact] = []
        var warnings: [String] = []

        for spec in rootSpecs() {
            guard FileManager.default.fileExists(atPath: spec.url.path) else { continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: spec.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )) ?? []

            for child in children {
                let childName = child.lastPathComponent
                // Never walk into an Apple folder, an installed app's support
                // folder, a vendor container, or a known system component.
                if BundleMatcher.isAppleIdentifier(childName) ||
                    isKnownSystemFolder(key: childName, displayName: childName) ||
                    index.matchesFolder(named: childName) {
                    continue
                }

                if let artifact = artifact(for: child, spec: spec, index: index) {
                    artifacts.append(artifact)
                    continue
                }
                guard spec.inspectOneLevel else { continue }

                // A vendor container such as `Microsoft` or `Google` is not an
                // app by itself; only inspect its children when the vendor is
                // not associated with a known installed app.
                if isVendorFolder(childName) || index.matchesVendorContainer(named: childName) {
                    continue
                }

                let grandchildren = (try? FileManager.default.contentsOfDirectory(
                    at: child,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )) ?? []
                for grandchild in grandchildren {
                    if isGenericSupportName(grandchild.lastPathComponent) { continue }
                    if let artifact = artifact(for: grandchild, spec: spec, index: index, nested: true) {
                        artifacts.append(artifact)
                    }
                }
            }
        }

        // Group helper identifiers under the owning bundle id.
        var grouped: [String: [Artifact]] = [:]
        for artifact in artifacts {
            grouped[groupingKey(artifact.key), default: []].append(artifact)
        }

        var groups: [OrphanGroup] = []
        for (key, items) in grouped {
            let uniqueURLs = Array(Set(items.map(\.url)))
            guard uniqueURLs.count >= 1 else { continue }
            let displayName = preferredDisplayName(for: key, items: items)
            guard !index.matches(key: key, displayName: displayName) else { continue }
            guard !BundleMatcher.isAppleIdentifier(key) else { continue }
            guard !BundleMatcher.isKnownBackgroundService(key) else { continue }
            guard !isKnownSystemFolder(key: key, displayName: displayName) else { continue }

            let categories = Set(items.map(\.category))
            let confidence = confidence(for: categories, count: items.count)
            var budget = 0
            let nodes = uniqueURLs.map { url in
                let matching = items.first { $0.url == url }
                return ResidueTreeBuilder.build(
                    url: url,
                    category: matching?.category ?? .other,
                    nodeBudget: &budget
                )
            }
            .sorted { $0.size > $1.size }

            let total = nodes.reduce(Int64(0)) { $0 + $1.size }
            let files = nodes.reduce(0) { $0 + max($1.fileCount, 1) }
            let modified = uniqueURLs.compactMap { FileSize.lastModified(of: $0) }.max()

            // A bare cache/log with no companion is noise, not a useful orphan.
            if items.count == 1,
               [.caches, .logs, .preferences, .httpStorages, .webKit, .savedState, .cookies].contains(items[0].category) {
                continue
            }
            // A single app-name folder is only interesting when the name looks
            // like a human app name (`Trae CN`), not an internal Chromium folder
            // (`Default`, `GraphiteDawnCache`) or an updater (`xxgg-electron`).
            if items.count == 1, key.hasPrefix("name:") {
                let name = items[0].displayName
                let human = name.contains(" ") || name.contains { !$0.isASCII }
                if !human { continue }
            }

            groups.append(OrphanGroup(
                id: key,
                key: key,
                displayName: displayName,
                confidence: confidence,
                artifacts: nodes,
                totalSize: total,
                fileCount: files,
                lastModified: modified
            ))
        }

        groups.sort { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            if lhs.totalSize != rhs.totalSize { return lhs.totalSize > rhs.totalSize }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        if groups.isEmpty {
            warnings.append("没有发现明显的孤儿残留。")
        }
        warnings.append("孤儿残留是启发式识别结果，默认不勾选；请展开确认后再清理。")

        return Result(groups: groups, warnings: warnings, scannedArtifacts: artifacts.count)
    }

    // MARK: - Artifact extraction

    private static func artifact(
        for url: URL,
        spec: RootSpec,
        index: InstalledIndex,
        nested: Bool = false
    ) -> Artifact? {
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return nil }
        if SafetyGuard.isSystemPath(url) { return nil }
        if SafetyGuard.requiresAdmin(url) && spec.category != .launchDaemons &&
            spec.category != .launchAgents && spec.category != .other {
            return nil
        }

        let key: String
        let displayName: String
        switch spec.category {
        case .preferences:
            let stem = url.deletingPathExtension().lastPathComponent
            guard BundleMatcher.looksLikeBundleIdentifier(stem) else { return nil }
            key = BundleMatcher.normalizedIdentifier(stem)
            displayName = stem
        case .launchAgents, .launchDaemons:
            guard url.pathExtension.lowercased() == "plist",
                  let dictionary = PlistReader.dictionary(at: url) else { return nil }
            let label = (dictionary["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
            guard BundleMatcher.looksLikeBundleIdentifier(label) || isAppLikeName(label) else { return nil }
            key = BundleMatcher.looksLikeBundleIdentifier(label)
                ? BundleMatcher.normalizedIdentifier(label)
                : "name:" + BundleMatcher.normalizeName(label)
            displayName = label
        case .containers, .groupContainers, .applicationScripts, .httpStorages, .webKit,
             .savedState, .cookies, .crashReports:
            let identifier = cleanedArtifactStem(name)
            guard BundleMatcher.looksLikeBundleIdentifier(identifier) else { return nil }
            key = BundleMatcher.normalizedIdentifier(identifier)
            displayName = identifier
        case .applicationSupport, .caches, .logs:
            // Known vendor containers (`Google`, `Microsoft`, …) are only
            // containers; inspect their children instead of flagging the vendor
            // folder itself.
            if isVendorFolder(name) { return nil }
            if BundleMatcher.looksLikeBundleIdentifier(cleanedArtifactStem(name)) {
                let identifier = cleanedArtifactStem(name)
                key = BundleMatcher.normalizedIdentifier(identifier)
                displayName = identifier
            } else if isAppLikeName(name) {
                key = "name:" + BundleMatcher.normalizeName(name)
                displayName = name
            } else if !nested, isVendorFolder(name) {
                return nil
            } else {
                return nil
            }
        case .plugins, .other:
            if let bundleID = BundleInspector.bundleID(at: url),
               BundleMatcher.looksLikeBundleIdentifier(bundleID) {
                key = BundleMatcher.normalizedIdentifier(bundleID)
                displayName = name
            } else if BundleMatcher.looksLikeBundleIdentifier(cleanedArtifactStem(name)) {
                key = BundleMatcher.normalizedIdentifier(cleanedArtifactStem(name))
                displayName = name
            } else {
                return nil
            }
        }

        guard !index.matches(key: key, displayName: displayName) else { return nil }
        return Artifact(
            url: url,
            category: spec.category,
            requiresAdmin: SafetyGuard.requiresAdmin(url),
            key: key,
            displayName: displayName
        )
    }

    // MARK: - Rules

    private static func cleanedArtifactStem(_ name: String) -> String {
        var value = name
        for suffix in [".savedState", ".binarycookies", ".plist"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value
    }

    private static func isAppLikeName(_ name: String) -> Bool {
        guard name.count >= 3, name.count <= 80 else { return false }
        guard !name.hasPrefix("com."), !name.hasPrefix("org."), !name.hasPrefix("net."),
              !name.hasPrefix("io.") else { return false }
        let hasSpace = name.contains(" ")
        let hasUppercase = name.contains { $0.isUppercase }
        let hasHyphen = name.contains("-")
        let hasNonASCII = name.contains { !$0.isASCII }
        return hasSpace || hasUppercase || hasHyphen || hasNonASCII
    }

    private static func isVendorFolder(_ name: String) -> Bool {
        installedNameAllowlistKeys.contains(BundleMatcher.normalizeName(name))
    }

    private static func isGenericSupportName(_ name: String) -> Bool {
        let normalized = BundleMatcher.normalizeName(name)
        let blocked: Set<String> = [
            "default", "cache", "caches", "codecache", "gpucache", "graphitedawncache",
            "dawngraphitecache", "dawnwebgpucache", "shadercache", "crashpad",
            "crashreports", "edgeupdater", "updater", "shipit", "sparkle", "installation",
            "fscacheddata", "xpcservice", "netstats", "tea", "apdb", "urlbags",
            "commercerequestcache", "servicelogs", "backups", "blobstorage",
            "indexeddb", "localstorage", "sessionstorage", "webstorage", "serviceworker",
            "network", "preferences", "localstate", "singletonlock", "singletoncookie",
            "singletonsocket", "cacheddata", "cachedprofilesdata", "cachedconfigurations",
            "cachedextensionvsixs", "logs", "temp", "tmp", "cachedb", "cachedbwal",
            "cachedbshm"
        ]
        return blocked.contains(normalized)
    }

    private static func isKnownSystemFolder(key: String, displayName: String) -> Bool {
        let normalized = key.hasPrefix("name:")
            ? String(key.dropFirst("name:".count))
            : BundleMatcher.normalizeName(key)
        let blocked: Set<String> = [
            "addressbook", "animoji", "askpermission", "callhistorydb",
            "callhistorytransactions", "clouddocs", "controlcenter", "crashreporter",
            "differentialprivacy", "diskimages", "facetime", "fileprovider",
            "google", "intelligenceflow", "knowledge", "logioptionsplus",
            "microsoft", "music", "openai", "spotlight", "xcode", "icloud",
            "icdd", "identityservicesd", "locationaccessstored",
            "networkserviceproxy", "tipsd", "familycircled", "homeenergyd",
            "contactsd", "appplaceholdersyncd", "apple", "adobe", "mozilla",
            "tencent", "bytedance", "jetbrains", "unity", "steam", "docker",
            "logitech", "oracle", "vmware", "parallels", "setapp", "homebrew",
            "askpermissiond", "installertelemetry", "chromecrashpadhandler",
            "isworkflowmyapp", "cachedb", "cachedbwal", "cachedbshm"
        ]
        return blocked.contains(normalized)
    }

    private static func preferredDisplayName(for key: String, items: [Artifact]) -> String {
        if key.hasPrefix("name:") {
            return items.first?.displayName ?? String(key.dropFirst("name:".count))
        }
        if let support = items.first(where: { $0.category == .applicationSupport }) {
            return support.displayName
        }
        if let first = items.first {
            return first.displayName
        }
        return key
    }

    private static func groupingKey(_ key: String) -> String {
        guard !key.hasPrefix("name:") else { return key }
        let suffixes = [".helper", ".shipit", ".updater", ".xpcservice", ".agent",
                        ".daemon", ".service", ".widget", ".widgets", ".extension",
                        ".framework", ".installer", ".launcher", ".desktophelper",
                        ".youdaowordservice", ".youdaofileextension"]
        var value = key
        for suffix in suffixes where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value
    }

    private static func confidence(for categories: Set<ResidueCategory>, count: Int) -> OrphanConfidence {
        var score = 0
        if categories.contains(.preferences) { score += 1 }
        if categories.contains(.applicationSupport) { score += 2 }
        if categories.contains(.containers) || categories.contains(.groupContainers) { score += 2 }
        if categories.contains(.launchAgents) || categories.contains(.launchDaemons) { score += 2 }
        if categories.contains(.caches) || categories.contains(.logs) { score += 1 }
        if count >= 2 { score += 1 }
        if score >= 4 { return .high }
        if score >= 2 { return .medium }
        return .low
    }

    private static func rootSpecs() -> [RootSpec] {
        let library = SafetyGuard.home.appendingPathComponent("Library", isDirectory: true)
        var specs: [RootSpec] = [
            RootSpec(url: library.appendingPathComponent("Preferences"), category: .preferences, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Caches"), category: .caches, inspectOneLevel: true),
            RootSpec(url: library.appendingPathComponent("Application Support"), category: .applicationSupport, inspectOneLevel: true),
            RootSpec(url: library.appendingPathComponent("Logs"), category: .logs, inspectOneLevel: true),
            RootSpec(url: library.appendingPathComponent("LaunchAgents"), category: .launchAgents, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Containers"), category: .containers, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Group Containers"), category: .groupContainers, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Application Scripts"), category: .applicationScripts, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("HTTPStorages"), category: .httpStorages, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("WebKit"), category: .webKit, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Saved Application State"), category: .savedState, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Cookies"), category: .cookies, inspectOneLevel: false)
        ]
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), category: .launchDaemons, inspectOneLevel: false))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/LaunchAgents"), category: .launchAgents, inspectOneLevel: false))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), category: .other, inspectOneLevel: false))
        return specs
    }
}

/// Known installed apps, used to avoid flagging their helpers as orphans.
private struct InstalledIndex {
    private let identifiers: Set<String>
    private let names: Set<String>
    private let vendorTokens: Set<String>

    init(apps: [AppInfo]) {
        var identifiers = Set<String>()
        var names = Set<String>()
        var vendors = Set<String>()
        for app in apps {
            if let bundleID = app.bundleID {
                let id = BundleMatcher.normalizedIdentifier(bundleID)
                identifiers.insert(id)
                let parts = id.components(separatedBy: ".")
                if parts.count >= 2, parts[1].count >= 4 {
                    vendors.insert(parts[1].lowercased())
                }
            }
            let name = BundleMatcher.normalizeName(app.name)
            if name.count >= 3 { names.insert(name) }
            if let executable = app.executableName {
                let exe = BundleMatcher.normalizeName(executable)
                if exe.count >= 3 { names.insert(exe) }
            }
        }
        self.identifiers = identifiers
        self.names = names
        self.vendorTokens = vendors
    }

    func matches(key: String, displayName: String) -> Bool {
        if key.hasPrefix("name:") {
            let name = String(key.dropFirst("name:".count))
            return matchesName(name) || matchesVendorToken(name)
        }
        let candidate = BundleMatcher.normalizedIdentifier(key)
        guard !candidate.isEmpty else { return false }
        for id in identifiers {
            if candidate == id { return true }
            if candidate.hasPrefix(id + ".") { return true }
            if candidate.hasSuffix("." + id) { return true }
            // Vendor-level key (`com.vendor`) with an installed app below it.
            if candidate.components(separatedBy: ".").count <= 2,
               id.hasPrefix(candidate + ".") {
                return true
            }
        }
        if matchesName(BundleMatcher.normalizeName(displayName)) { return true }
        if matchesVendorToken(candidate) { return true }
        return false
    }

    /// True when a top-level support folder belongs to an installed app or to a
    /// vendor with at least one installed app. This prevents walking into
    /// `Microsoft Edge/Default` or `Doubao/GraphiteDawnCache` and calling the
    /// children orphans.
    func matchesFolder(named name: String) -> Bool {
        let normalized = BundleMatcher.normalizeName(name)
        if matchesName(normalized) { return true }
        if matchesVendorToken(normalized) { return true }
        let identifier = BundleMatcher.normalizedIdentifier(name)
        for id in identifiers {
            if identifier == id { return true }
            if identifier.hasPrefix(id + ".") { return true }
            if id.hasPrefix(identifier + ".") { return true }
        }
        return false
    }

    func matchesVendorContainer(named name: String) -> Bool {
        matchesVendorToken(BundleMatcher.normalizeName(name))
    }

    private func matchesName(_ normalized: String) -> Bool {
        guard normalized.count >= 3 else { return false }
        if names.contains(normalized) { return true }
        return names.contains { installed in
            installed.count >= 4 && (installed.hasSuffix(normalized) || normalized.hasSuffix(installed))
        }
    }

    private func matchesVendorToken(_ normalized: String) -> Bool {
        vendorTokens.contains { token in
            token.count >= 4 && normalized.contains(token)
        }
    }
}
