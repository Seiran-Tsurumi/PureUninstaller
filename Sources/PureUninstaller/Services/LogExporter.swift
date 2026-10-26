import Foundation
import AppKit
import UniformTypeIdentifiers

/// Builds and exports the plain-text uninstall log.
enum LogExporter {
    static func export(text: String, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "导出卸载日志"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法写入日志"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
            return nil
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func defaultName(appName: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = appName.replacingOccurrences(of: "/", with: "-")
        return "Uninstall-\(safeName)-\(formatter.string(from: date)).txt"
    }
}
