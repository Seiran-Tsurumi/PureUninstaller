import Foundation
import AppKit

/// Optional, user-authorized administrator removal for root-owned app bundles.
///
/// This is intentionally narrow:
/// - only `.app` bundles inside `/Applications` or `~/Applications`;
/// - never `/System`, SIP apps, net-self, or arbitrary residue paths;
/// - no persistent privileged helper;
/// - the user sees the macOS administrator password dialog every time.
///
/// The implementation uses AppleScript's `do shell script … with administrator
/// privileges`, which is the standard one-shot authorization path for a local
/// utility. Paths are validated and shell-quoted before they reach `/bin/rm` or
/// `/bin/mv`; no user text is interpolated as a command.
enum AdminRemovalService {
    struct Request: Sendable {
        let url: URL
        let size: Int64
    }

    struct Command {
        let request: Request
        let destination: URL?
        let shell: String
    }

    @MainActor
    static func remove(_ requests: [Request], mode: DeletionMode) async -> [DeletionRecord] {
        guard !requests.isEmpty else { return [] }

        var valid: [Request] = []
        var invalid: [DeletionRecord] = []
        for request in requests {
            let path = request.url.path
            let controlFree = !path.contains("\n") && !path.contains("\r")
            if controlFree && SafetyGuard.isAdminRemovableAppBundle(request.url) {
                valid.append(request)
            } else {
                invalid.append(DeletionRecord(
                    url: request.url,
                    size: request.size,
                    success: false,
                    message: "失败：该路径不允许使用管理员移除（仅限非系统 .app 应用本体）。",
                    isPermissionError: false
                ))
            }
        }
        guard !valid.isEmpty else { return invalid }

        var commands: [Command] = []
        for request in valid {
            switch mode {
            case .trash:
                let destination = TrashMover.destination(for: request.url)
                let shell = "/bin/mv -f \(shellQuote(request.url.path)) \(shellQuote(destination.path))"
                commands.append(Command(request: request, destination: destination, shell: shell))
            case .permanent:
                let shell = "/bin/rm -rf \(shellQuote(request.url.path))"
                commands.append(Command(request: request, destination: nil, shell: shell))
            }
        }

        let shellCommand = commands.map(\.shell).joined(separator: "; ")
        let source = "do shell script \"\(appleScriptEscape(shellCommand))\" with administrator privileges"
        var scriptError: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&scriptError)

        let errorNumber = scriptError?["NSAppleScriptErrorNumber"] as? Int
        let errorMessage = scriptError?["NSAppleScriptErrorMessage"] as? String
        let cancelled = errorNumber == -128

        var records: [DeletionRecord] = []
        for command in commands {
            let gone = !FileManager.default.fileExists(atPath: command.request.url.path)
            if gone {
                let message: String
                switch mode {
                case .trash:
                    message = "已由管理员移到废纸篓（兼容模式，可从废纸篓手动拖回）"
                case .permanent:
                    message = "已由管理员永久删除"
                }
                records.append(DeletionRecord(
                    url: command.request.url,
                    size: command.request.size,
                    success: true,
                    message: message
                ))
            } else {
                let reason: String
                if cancelled {
                    reason = "已取消管理员授权"
                } else if let errorMessage, !errorMessage.isEmpty {
                    reason = errorMessage
                } else {
                    reason = "管理员操作未完成"
                }
                records.append(DeletionRecord(
                    url: command.request.url,
                    size: command.request.size,
                    success: false,
                    message: "失败：\(reason)（应用本体仍存在）",
                    isPermissionError: false
                ))
            }
        }
        return invalid + records
    }

    private static func shellQuote(_ value: String) -> String {
        // POSIX single-quote: ' -> '\''
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
