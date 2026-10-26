import Foundation

enum UninstallMode: String, Sendable {
    case normal
    case force

    var title: String {
        switch self {
        case .normal: return "普通卸载"
        case .force: return "强制卸载"
        }
    }

    var explanation: String {
        switch self {
        case .normal:
            return "优先使用应用自带卸载器，然后结束进程、扫描并清理残留。"
        case .force:
            return "跳过官方卸载器，强制结束关联进程后深度清理。适用于应用损坏、无法退出或主程序已丢失的情况。"
        }
    }
}

enum DeletionMode: String, Sendable {
    case trash
    case permanent

    var title: String {
        switch self {
        case .trash: return "移到废纸篓"
        case .permanent: return "永久删除"
        }
    }
}

/// A vendor uninstaller found next to or inside an app.
struct UninstallerCandidate: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case script
    }

    let id: String
    let url: URL
    let appName: String
    let kind: Kind

    init(url: URL, appName: String, kind: Kind) {
        self.id = url.path
        self.url = url
        self.appName = appName
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .application: return "官方卸载器"
        case .script: return "官方卸载脚本"
        }
    }
}

struct AppProcess: Identifiable, Hashable, Sendable {
    let pid: pid_t
    let name: String
    let command: String
    let isGUI: Bool

    var id: pid_t { pid }
}

struct DeletionRecord: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let size: Int64
    let success: Bool
    let message: String
    /// True when macOS/TCC denied the operation (usually missing Full Disk Access).
    let isPermissionError: Bool

    init(url: URL, size: Int64, success: Bool, message: String, isPermissionError: Bool = false) {
        self.id = UUID()
        self.url = url
        self.size = size
        self.success = success
        self.message = message
        self.isPermissionError = isPermissionError
    }
}

struct UninstallResult: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let deletedCount: Int
    let failedCount: Int
    /// Bytes permanently removed from disk (only for `permanent` mode).
    let freedBytes: Int64
    /// Bytes moved to the Trash; space is reclaimed after the Trash is emptied.
    let trashedBytes: Int64
    let records: [DeletionRecord]
    let logText: String
    let finishedAt: Date

    var failures: [DeletionRecord] { records.filter { !$0.success } }

    /// The UI shows a Full Disk Access guide when at least one item was denied
    /// by TCC. This is the most common cause of a 0-success uninstall.
    var needsFullDiskAccess: Bool { records.contains { $0.isPermissionError } }
}
