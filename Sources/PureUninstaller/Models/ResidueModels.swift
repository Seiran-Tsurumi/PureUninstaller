import Foundation

/// Categories shown as badges in the residue tree.
enum ResidueCategory: String, CaseIterable, Sendable {
    case preferences
    case caches
    case applicationSupport
    case logs
    case launchAgents
    case launchDaemons
    case containers
    case groupContainers
    case applicationScripts
    case httpStorages
    case webKit
    case savedState
    case cookies
    case plugins
    case crashReports
    case other

    var title: String {
        switch self {
        case .preferences: return "偏好设置"
        case .caches: return "缓存"
        case .applicationSupport: return "应用数据"
        case .logs: return "日志"
        case .launchAgents: return "LaunchAgent"
        case .launchDaemons: return "LaunchDaemon"
        case .containers: return "沙盒容器"
        case .groupContainers: return "共享容器"
        case .applicationScripts: return "应用脚本"
        case .httpStorages: return "HTTP 存储"
        case .webKit: return "WebKit 数据"
        case .savedState: return "窗口状态"
        case .cookies: return "Cookies"
        case .plugins: return "插件 / 扩展"
        case .crashReports: return "崩溃记录"
        case .other: return "其他"
        }
    }

    var icon: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .caches: return "internaldrive"
        case .applicationSupport: return "folder"
        case .logs: return "doc.text"
        case .launchAgents, .launchDaemons: return "gearshape.2"
        case .containers, .groupContainers: return "shippingbox"
        case .applicationScripts: return "applescript"
        case .httpStorages: return "network"
        case .webKit: return "safari"
        case .savedState: return "macwindow"
        case .cookies: return "circle.grid.cross"
        case .plugins: return "puzzlepiece.extension"
        case .crashReports: return "exclamationmark.triangle"
        case .other: return "doc"
        }
    }

    /// Higher risk means the path is more likely to contain user-created data.
    var risk: ResidueRisk {
        switch self {
        case .preferences, .caches, .logs, .crashReports, .httpStorages, .webKit,
             .savedState, .cookies:
            return .low
        case .applicationSupport, .applicationScripts, .plugins:
            return .medium
        case .containers, .groupContainers, .launchAgents, .launchDaemons, .other:
            return .high
        }
    }

    var isRootLevel: Bool {
        self == .launchDaemons
    }
}

enum ResidueRisk: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    var title: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "含用户数据"
        case .high: return "高风险"
        }
    }

    static func < (lhs: ResidueRisk, rhs: ResidueRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One node in the residue preview tree.
///
/// Directories keep their children so `OutlineGroup` can expand them. Sizes are
/// allocated sizes (the number Finder shows), summed recursively at scan time.
struct ResidueNode: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let category: ResidueCategory
    /// Root-owned system paths are listed for transparency but cannot be
    /// selected or deleted by this process.
    let requiresAdmin: Bool
    let isDeletable: Bool
    let isAppBody: Bool
    let children: [ResidueNode]?

    init(
        id: String,
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        category: ResidueCategory,
        requiresAdmin: Bool,
        isDeletable: Bool,
        isAppBody: Bool = false,
        children: [ResidueNode]? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.category = category
        self.requiresAdmin = requiresAdmin
        self.isDeletable = isDeletable
        self.isAppBody = isAppBody
        self.children = children
    }

    var risk: ResidueRisk { isAppBody ? .high : category.risk }

    var icon: String {
        if isAppBody { return "app" }
        if isDirectory { return category.icon }
        return "doc"
    }

    /// Every path in this subtree, including the node itself.
    var allPaths: [String] {
        var result = [id]
        if let children {
            for child in children {
                result.append(contentsOf: child.allPaths)
            }
        }
        return result
    }

    /// Number of regular files represented by this node.
    var fileCount: Int {
        guard isDirectory, let children else { return isDirectory ? 0 : 1 }
        return children.reduce(0) { partial, child in
            partial + (child.isDirectory ? max(child.fileCount, 1) : 1)
        }
    }

    /// A node is selectable only when it is user-owned and inside an allowed path.
    var isSelectable: Bool { isDeletable && !requiresAdmin }

    static func == (lhs: ResidueNode, rhs: ResidueNode) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// An app that is still installed, plus the residue roots found for it.
struct UninstallTarget: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let app: AppInfo?
    let appBody: ResidueNode?
    let residues: [ResidueNode]
    let uninstaller: UninstallerCandidate?

    var allRoots: [ResidueNode] {
        var roots: [ResidueNode] = []
        if let appBody { roots.append(appBody) }
        roots.append(contentsOf: residues)
        return roots
    }

    var totalSize: Int64 {
        allRoots.reduce(0) { $0 + $1.size }
    }

    var fileCount: Int {
        allRoots.reduce(0) { $0 + max($1.fileCount, 1) }
    }
}

enum OrphanConfidence: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    var title: String {
        switch self {
        case .high: return "高置信"
        case .medium: return "中置信"
        case .low: return "低置信"
        }
    }

    var icon: String {
        switch self {
        case .high: return "checkmark.seal"
        case .medium: return "questionmark.circle"
        case .low: return "exclamationmark.circle"
        }
    }

    static func < (lhs: OrphanConfidence, rhs: OrphanConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A group of leftovers that appear to belong to an app no longer installed.
///
/// This is intentionally heuristic. The UI labels these as “可能” and defaults
/// them to unselected so a false positive never becomes a one-click deletion.
struct OrphanGroup: Identifiable, Hashable, Sendable {
    let id: String
    let key: String
    let displayName: String
    let confidence: OrphanConfidence
    let artifacts: [ResidueNode]
    let totalSize: Int64
    let fileCount: Int
    let lastModified: Date?

    static func == (lhs: OrphanGroup, rhs: OrphanGroup) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
