import Foundation

/// Finds a vendor-supplied uninstaller without executing it.
///
/// The UI opens the found item so the vendor's own flow stays in control. The
/// app never runs an arbitrary bundled shell script silently.
enum UninstallerLocator {
    static func find(for app: AppInfo) -> UninstallerCandidate? {
        if let sibling = siblingUninstaller(for: app) {
            return sibling
        }
        return embeddedUninstaller(for: app)
    }

    private static func siblingUninstaller(for app: AppInfo) -> UninstallerCandidate? {
        let parent = app.url.deletingLastPathComponent()
        let children = (try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let candidates = children.filter { url in
            let name = url.lastPathComponent.lowercased()
            guard name.contains("uninstall") || name.contains("卸载") else { return false }
            guard url.pathExtension.lowercased() == "app" else { return false }
            return true
        }

        // Prefer a sibling whose name also mentions the app.
        let appKey = BundleMatcher.normalizeName(app.name)
        let best = candidates.first { candidate in
            BundleMatcher.normalizeName(candidate.lastPathComponent).contains(appKey)
        } ?? candidates.first

        guard let best else { return nil }
        return UninstallerCandidate(url: best, appName: app.name, kind: .application)
    }

    private static func embeddedUninstaller(for app: AppInfo) -> UninstallerCandidate? {
        let searchRoots = [
            app.url.appendingPathComponent("Contents/Resources"),
            app.url.appendingPathComponent("Contents/SharedSupport"),
            app.url.appendingPathComponent("Contents/Helpers"),
            app.url.appendingPathComponent("Contents/Library")
        ]

        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                guard name.contains("uninstall") || name.contains("卸载") else { continue }
                let ext = url.pathExtension.lowercased()
                if ext == "app" {
                    return UninstallerCandidate(url: url, appName: app.name, kind: .application)
                }
                if ["command", "sh", "tool", "scpt"].contains(ext) {
                    return UninstallerCandidate(url: url, appName: app.name, kind: .script)
                }
                // Do not descend into arbitrary resource directories looking for
                // helpers; one level below the known roots is enough.
                enumerator.skipDescendants()
            }
        }
        return nil
    }
}
