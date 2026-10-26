import Foundation
import AppKit

/// Where an application bundle came from.
enum AppSource: String, Codable, Sendable {
    case appStore
    case developerID
    case localSignature
    case unsigned
    case appleSystem
    case unknown

    var title: String {
        switch self {
        case .appStore: return "App Store"
        case .developerID: return "开发者签名"
        case .localSignature: return "本地签名"
        case .unsigned: return "未签名"
        case .appleSystem: return "macOS 系统"
        case .unknown: return "未知"
        }
    }
}

/// The folder class an app lives in. System apps are displayed but never touched.
enum AppLocation: String, Codable, Sendable {
    case system
    case applications
    case userApplications
    case other

    var title: String {
        switch self {
        case .system: return "系统"
        case .applications: return "/Applications"
        case .userApplications: return "~/Applications"
        case .other: return "其他位置"
        }
    }
}

/// A single `.app` bundle discovered on disk.
///
/// `id` is the standardized bundle path. It is stable enough for table selection
/// and avoids relying on a bundle identifier that some unsigned apps do not have.
struct AppInfo: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let bundleID: String?
    let version: String
    let build: String
    let size: Int64
    let source: AppSource
    let location: AppLocation
    let isSystem: Bool
    let executableName: String?
    let teamID: String?
    let signingAuthority: String?
    var isRunning: Bool
    /// Uninstaller helpers are hidden from the normal app list but still usable
    /// by `UninstallerLocator` when an app ships one.
    let isUninstaller: Bool

    var versionDisplay: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false) where version != build:
            return "\(version) (\(build))"
        case (false, _):
            return version
        case (true, false):
            return build
        default:
            return "—"
        }
    }

    var parentDirectory: URL { url.deletingLastPathComponent() }

    /// Exact install folder. `/Applications/Work` is shown as such instead of
    /// being collapsed to `/Applications`.
    var installLocationDisplay: String {
        if isSystem { return "系统" }
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let homePath = SafetyGuard.home.path
        if parent == homePath + "/Applications" { return "~/Applications" }
        if parent.hasPrefix(homePath + "/") {
            return "~" + parent.dropFirst(homePath.count)
        }
        return parent
    }

    /// App bundles inside a system path or a SIP-protected cryptex are read-only
    /// in this tool. The UI also uses this property to grey out rows.
    var canBeUninstalled: Bool { !isSystem && !isUninstaller }

    /// Root-owned app bundles, or bundles inside an unwritable parent, need
    /// the optional administrator path.
    var requiresAdminRemoval: Bool {
        guard canBeUninstalled else { return false }
        return !FileManager.default.isWritableFile(atPath: url.path) ||
            !SafetyGuard.parentIsWritable(url)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
