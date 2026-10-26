import Foundation

/// `FileManager.trashItem` asks macOS to build a “Put Back” record and can
/// reject root-owned app bundles with a misleading diagnostic-report error.
/// A rename into `~/.Trash` only needs write permission on the source parent
/// and the Trash folder, so it works for root-owned bundles without weakening
/// SIP or asking for admin rights.
enum TrashMover {
    static func moveToTrash(_ url: URL) throws -> URL {
        let trash = SafetyGuard.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        let destination = uniqueDestination(for: url, in: trash)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    /// Public within the module so the admin path can choose the same unique
    /// Trash name before invoking `/bin/mv` as root.
    static func destination(for url: URL) -> URL {
        let trash = SafetyGuard.home.appendingPathComponent(".Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return uniqueDestination(for: url, in: trash)
    }

    private static func uniqueDestination(for url: URL, in trash: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var index = 1
        while true {
            let name = index == 1 ? "\(base)\(suffix)" : "\(base) \(index)\(suffix)"
            let candidate = trash.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
