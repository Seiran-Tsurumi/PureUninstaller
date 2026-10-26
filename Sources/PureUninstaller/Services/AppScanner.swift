import Foundation

/// Discovers app bundles in the standard application locations.
enum AppScanner {
    static var roots: [URL] {
        var result: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            SafetyGuard.home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true)
        ]
        let safariCryptex = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
                                isDirectory: true)
        if FileManager.default.fileExists(atPath: safariCryptex.path) {
            result.append(safariCryptex)
        }
        return result
    }

    static func scan() async -> [AppInfo] {
        let urls = collectAppURLs()
        guard !urls.isEmpty else { return [] }

        var apps: [AppInfo] = []
        let chunks = urls.chunked(into: 6)
        for chunk in chunks {
            let partial = await withTaskGroup(of: AppInfo?.self) { group -> [AppInfo] in
                for url in chunk {
                    group.addTask {
                        BundleInspector.inspect(url: url)
                    }
                }
                var values: [AppInfo] = []
                for await value in group {
                    if let value { values.append(value) }
                }
                return values
            }
            apps.append(contentsOf: partial)
        }

        // Uninstallers are hidden from the main list. They remain discoverable
        // per-app through `UninstallerLocator`.
        apps = apps.filter { !$0.isUninstaller }

        // Never offer to uninstall the running utility itself.
        let selfPath = Bundle.main.bundleURL.standardizedFileURL.path
        let selfID = Bundle.main.bundleIdentifier
        apps = apps.filter { app in
            if app.url.standardizedFileURL.path == selfPath { return false }
            if app.bundleID == "com.pureuninstaller.app" { return false }
            if let selfID, app.bundleID == selfID { return false }
            return true
        }

        // De-duplicate by standardized path in case a root overlaps.
        var seen = Set<String>()
        apps = apps.filter { app in
            guard !seen.contains(app.id) else { return false }
            seen.insert(app.id)
            return true
        }

        // User apps first, then system apps; each group alphabetically.
        apps.sort { lhs, rhs in
            if lhs.isSystem != rhs.isSystem { return !lhs.isSystem }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return comparison == .orderedAscending
        }
        return apps
    }

    /// Inspect a single app, e.g. one dropped on the window.
    static func inspectDropped(url: URL) -> AppInfo? {
        let normalized = url.standardizedFileURL
        guard normalized.pathExtension.lowercased() == "app" else { return nil }
        return BundleInspector.inspect(url: normalized)
    }

    private static func collectAppURLs() -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]

        for root in roots {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                defer { enumerator.skipDescendants() }

                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true { continue }
                let standardized = url.standardizedFileURL
                guard !isNestedInPackage(standardized) else { continue }
                guard seen.insert(standardized.path).inserted else { continue }
                result.append(standardized)
            }
        }
        return result
    }

    /// A `.app` inside a `.bundle`/`.framework`/`.plugin` is a helper, not a
    /// user-facing application. Such nested helpers are excluded from the list.
    private static func isNestedInPackage(_ url: URL) -> Bool {
        let packageExtensions: Set<String> = ["bundle", "framework", "plugin", "xpc", "app"]
        return url.pathComponents.dropLast().contains { component in
            packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
