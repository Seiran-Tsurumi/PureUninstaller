import Foundation
import AppKit
import Darwin

/// Finds and terminates processes associated with an app.
///
/// Matching is deliberately narrow: a process must reference the app bundle
/// path, its bundle identifier, or one of its known support folders. This avoids
/// the classic “kill every process whose name contains Foo” mistake.
enum ProcessManager {
    struct TerminationRecord: Sendable {
        let process: AppProcess
        let success: Bool
        let message: String
    }

    static func processes(for app: AppInfo) async -> [AppProcess] {
        let running = await MainActor.run { () -> [AppProcess] in
            NSWorkspace.shared.runningApplications.compactMap { runningApp in
                guard runningApp.processIdentifier != getpid() else { return nil }
                let bundled = runningApp.bundleURL?.standardizedFileURL.path
                let identifierMatch = app.bundleID != nil &&
                    runningApp.bundleIdentifier?.caseInsensitiveCompare(app.bundleID ?? "") == .orderedSame
                let pathMatch = bundled.map { SafetyGuard.isInside($0, app.url.path) } ?? false
                guard identifierMatch || pathMatch else { return nil }
                return AppProcess(
                    pid: runningApp.processIdentifier,
                    name: runningApp.localizedName ?? runningApp.bundleIdentifier ?? "进程",
                    command: bundled ?? runningApp.executableURL?.path ?? "",
                    isGUI: true
                )
            }
        }

        let commandLines = psSnapshot()
        var result = running
        var seen = Set(result.map(\.pid))

        for entry in commandLines {
            guard entry.pid != getpid(), entry.pid > 1 else { continue }
            guard !seen.contains(entry.pid) else { continue }
            guard matches(command: entry.command, app: app) else { continue }
            seen.insert(entry.pid)
            result.append(AppProcess(
                pid: entry.pid,
                name: executableName(from: entry.command),
                command: entry.command,
                isGUI: false
            ))
        }

        return result.sorted { lhs, rhs in
            if lhs.isGUI != rhs.isGUI { return lhs.isGUI }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func terminate(_ process: AppProcess, force: Bool) async -> TerminationRecord {
        if process.isGUI {
            let running = await MainActor.run {
                NSRunningApplication(processIdentifier: process.pid)
            }
            if let running {
                let requested = await MainActor.run {
                    force ? running.forceTerminate() : running.terminate()
                }
                if requested, await waitUntilGone(pid: process.pid, timeout: force ? 1.0 : 2.0) {
                    return TerminationRecord(process: process, success: true,
                                             message: force ? "已强制结束" : "已结束")
                }
            }
        }

        let signal = force ? SIGKILL : SIGTERM
        let sent = kill(process.pid, signal) == 0
        guard sent else {
            return TerminationRecord(process: process, success: false,
                                     message: "无法结束（权限不足或进程已退出）")
        }
        if await waitUntilGone(pid: process.pid, timeout: force ? 1.0 : 2.0) {
            return TerminationRecord(process: process, success: true,
                                     message: force ? "已强制结束" : "已结束")
        }
        return TerminationRecord(process: process, success: false,
                                 message: force ? "强制结束后进程仍存在" : "进程未退出，可尝试强制卸载")
    }

    static func terminateAll(_ processes: [AppProcess], force: Bool) async -> [TerminationRecord] {
        var records: [TerminationRecord] = []
        for process in processes {
            records.append(await terminate(process, force: force))
        }
        return records
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: - Private

    private struct CommandLine {
        let pid: pid_t
        let command: String
    }

    private static func psSnapshot() -> [CommandLine] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            let pidString = String(trimmed[..<space])
            guard let pid = pid_t(pidString) else { return nil }
            let command = String(trimmed[trimmed.index(after: space)...])
                .trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return nil }
            return CommandLine(pid: pid, command: command)
        }
    }

    private static func matches(command: String, app: AppInfo) -> Bool {
        if command.contains(app.url.path) { return true }
        if let bundleID = app.bundleID, !bundleID.isEmpty,
           command.localizedCaseInsensitiveContains(bundleID) {
            return true
        }
        // User-level background helpers often live in Application Support.
        let support = SafetyGuard.home
            .appendingPathComponent("Library/Application Support/\(app.name)")
            .path
        if command.contains(support) { return true }
        return false
    }

    private static func executableName(from command: String) -> String {
        let first = command.split(separator: " ").first.map(String.init) ?? command
        return URL(fileURLWithPath: first).lastPathComponent
    }

    private static func waitUntilGone(pid: pid_t, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isAlive(pid) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !isAlive(pid)
    }
}
