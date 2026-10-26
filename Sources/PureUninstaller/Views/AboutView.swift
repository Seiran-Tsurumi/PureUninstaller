import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("净卸")
                        .font(.system(size: 20, weight: .semibold))
                    Text("版本 \(version) (\(build)) · Apple Silicon · macOS 14+")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            DividerLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(
                        title: "只做卸载与清理",
                        lines: [
                            "扫描 /Applications、~/Applications 和系统应用目录。",
                            "普通卸载优先打开应用自带卸载器，再结束进程、扫描用户库残留。",
                            "强制卸载跳过厂商卸载器，强制结束关联进程后深度清理。",
                            "残留以树形列表展示，可逐项取消勾选后再清理。",
                            "支持批量选择、搜索、孤儿残留分析、进程查看和日志导出。"
                        ]
                    )
                    section(
                        title: "安全边界",
                        lines: [
                            "不修改 /System，不关闭 SIP，不修改系统快照。",
                            "系统自带应用只展示、置灰、不可选中，也不扫描其残留。",
                            "默认不请求管理员权限；root-owned App 可选“管理员权限移除”，每次都会弹出系统密码。不安装常驻 helper，不修改系统保护区域。",
                            "卸载普通 App 需要 macOS“完全磁盘访问权限”；root-owned App 可选“管理员权限移除”，每次都会弹出系统密码。",
                            "可选的管理员移除只针对 /Applications 或 ~/Applications 里的非系统 .app，不安装常驻 helper，不修改 /System 或 SIP。",
                            "默认移到废纸篓；只有手动切换到“永久删除”并在二次确认后才不可恢复。",
                            "关闭主窗口即完全退出，不常驻后台，不添加登录项。"
                        ]
                    )
                    section(
                        title: "说明",
                        lines: [
                            "孤儿残留通过 Bundle ID、应用名和 LaunchAgent 启发式识别，默认不勾选。",
                            "/Library/LaunchDaemons 等系统级项目会展示，但需要管理员权限，净卸不会自动删除。"
                        ]
                    )
                }
                .padding(20)
            }

            DividerLine()

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 560, height: 540)
    }

    private func section(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(line)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
