import Foundation
import AppKit
import Darwin

/// Full Disk Access is a macOS privacy permission (TCC), not root/admin.
///
/// macOS protects other apps' bundles and sandbox containers. A normal app
/// cannot move them to the Trash without this permission, even when the Unix
/// parent directory is writable. This helper detects the most common case and
/// gives the user a direct path to the correct System Settings pane.
enum PermissionGuide {
    /// There is no public “is FDA granted?” API. TCC.db is not present in
    /// `~/Library/Application Support` on current macOS, so probe real
    /// protected user data instead. Messages / Mail directories are protected
    /// by TCC and exist on virtually every Mac.
    private static var probeCandidates: [URL] {
        let library = SafetyGuard.home.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Messages", isDirectory: true),
            library.appendingPathComponent("Mail", isDirectory: true),
            library.appendingPathComponent("Safari/History.db"),
            library.appendingPathComponent("Application Support/MobileSync", isDirectory: true),
            library.appendingPathComponent("HomeKit", isDirectory: true)
        ]
    }

    static func hasFullDiskAccess() -> Bool {
        for url in probeCandidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil {
                    return true
                }
            } else {
                guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? handle.close() }
                if (try? handle.read(upToCount: 1)) != nil { return true }
            }
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openAppManagementSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Classify the opaque FileManager / TCC errors returned by `trashItem`.
    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            // NSFileReadNoPermissionError, NSFileWriteNoPermissionError,
            // NSFileWriteVolumeReadOnlyError and related file-access failures.
            if [257, 512, 513, 642, 640].contains(ns.code) { return true }
        }
        if ns.domain == NSPOSIXErrorDomain {
            if ns.code == Int(EACCES) || ns.code == Int(EPERM) { return true }
        }
        let text = ns.localizedDescription + " " + String(describing: ns.userInfo)
        let lowered = text.lowercased()
        return lowered.contains("permission") ||
            lowered.contains("not permitted") ||
            text.contains("许可") ||
            text.contains("权限") ||
            text.contains("拒绝")
    }

    static func message(for error: Error) -> String {
        let ns = error as NSError
        if isPermissionError(error) {
            return "失败：macOS 拒绝了访问，需要“完全磁盘访问权限”。请在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中授权净卸后重试。原始错误：\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
        }
        return "失败：\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
    }
}
