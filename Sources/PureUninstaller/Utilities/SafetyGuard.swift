import Foundation

/// Central deletion policy.
///
/// The app deliberately has no privileged helper, no `sudo`, no AppleScript
/// admin prompt and no way to touch `/System`. Every deletion path is checked
/// here even if the UI already disabled the row.
enum SafetyGuard {
    enum Kind: Sendable {
        case appBundle
        case residue
    }

    enum Decision: Equatable {
        case allowed
        case requiresAdmin
        case refused(String)

        var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    static let userLibrary = home.appendingPathComponent("Library", isDirectory: true).standardizedFileURL

    /// Paths that are never scanned as residue roots and never deleted.
    private static let forbiddenPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/private",
        "/dev",
        "/cores",
        "/Volumes",
        "/Library/Apple",
        "/Library/Developer",
        "/Library/Extensions",
        "/Library/Frameworks",
        "/Library/Keychains",
        "/Library/Security",
        "/Library/Updates",
        "/Library/Receipts",
        "/Library/SystemProfiling"
    ]

    /// User data that is never part of an app-uninstall residue. These folders
    /// are sensitive even if an app name happens to match.
    private static let protectedUserSubpaths: [String] = [
        "Library/Keychains",
        "Library/Messages",
        "Library/Mail",
        "Library/Safari",
        "Library/Photos",
        "Library/CloudStorage",
        "Library/Mobile Documents",
        "Library/Shortcuts",
        "Library/IdentityServices",
        "Library/HomeKit",
        "Library/Accounts"
    ]

    static func isSystemPath(_ url: URL) -> Bool {
        let original = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        return original.hasPrefix("/System/") ||
            resolved.hasPrefix("/System/") ||
            original == "/System" || resolved == "/System"
    }

    /// System apps live under `/System` (including Safari's Cryptex symlink).
    static func isSystemAppBundle(_ url: URL) -> Bool {
        isSystemPath(url)
    }

    static func isInside(_ path: String, _ parent: String) -> Bool {
        if path == parent { return true }
        return path.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    static func validateDeletion(of url: URL, kind: Kind) -> Decision {
        let path = url.standardizedFileURL.path
        guard path != "/" else { return .refused("不能删除根目录") }

        // Refuse symlinks whose target lives in a forbidden system location.
        // Deleting the link itself would be harmless, but refusing is simpler
        // and prevents surprising edge cases.
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        for prefix in forbiddenPrefixes where isInside(resolved, prefix) {
            return .refused("系统保护路径：\(prefix)")
        }

        for prefix in forbiddenPrefixes where isInside(path, prefix) {
            return .refused("系统保护路径：\(prefix)")
        }

        for relative in protectedUserSubpaths {
            let protected = home.appendingPathComponent(relative).standardizedFileURL.path
            if isInside(path, protected) || isInside(resolved, protected) {
                return .refused("受保护的用户数据：\(relative)")
            }
        }

        switch kind {
        case .appBundle:
            guard path.hasSuffix(".app") else { return .refused("不是应用包") }
            guard !isSystemAppBundle(url) else { return .refused("系统应用受 SIP 保护") }
            let parent = url.deletingLastPathComponent().standardizedFileURL.path
            let allowedParents = [
                "/Applications",
                home.appendingPathComponent("Applications").standardizedFileURL.path
            ]
            guard allowedParents.contains(where: { isInside(path, $0) && parent != "/" }) else {
                return .refused("应用不在可卸载目录")
            }
            guard parentIsWritable(url) else {
                return .refused("应用所在目录不可写，请在 Finder 中手动移除")
            }
            return .allowed

        case .residue:
            guard isInside(path, userLibrary.path), path != userLibrary.path else {
                // Root-level /Library daemons are visible in the preview but are
                // intentionally never deleted by the app.
                if isInside(path, "/Library") {
                    return .requiresAdmin
                }
                return .refused("不在用户库范围内")
            }
            guard isInside(path, userLibrary.path), path != userLibrary.path else {
                return .refused("不能删除用户库根目录")
            }
            guard parentIsWritable(url) else {
                return .refused("文件受系统保护或父目录不可写")
            }
            return .allowed
        }
    }

    /// A directory is deletable when its parent is writable. For a file, the
    /// containing directory's write bit is what matters for unlinking.
    static func parentIsWritable(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    static func isReadable(_ url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }

    /// Paths under `/Library` are scanned for transparency, but the app never
    /// asks for administrator rights. They render with a lock.
    static func requiresAdmin(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return isInside(path, "/Library")
    }

    /// Only a non-system `.app` inside the two application roots may use the
    /// optional administrator path. This is deliberately narrower than the
    /// general residue scanner.
    static func isAdminRemovableAppBundle(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.hasSuffix(".app") else { return false }
        guard !isSystemAppBundle(url) else { return false }
        let apps = home.appendingPathComponent("Applications").standardizedFileURL.path
        if path == Bundle.main.bundleURL.standardizedFileURL.path { return false }
        return isInside(path, "/Applications") || isInside(path, apps)
    }

    static func isDeletableResidue(_ url: URL) -> Bool {
        validateDeletion(of: url, kind: .residue).isAllowed
    }
}
