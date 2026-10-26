import SwiftUI
import AppKit

/// Slim, non-modal banner shown when Full Disk Access is missing.
///
/// A popup on every launch would be annoying, so the app explains the
/// requirement inline and keeps a shield status button in the header.
struct PermissionBanner: View {
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("需要“完全磁盘访问权限”")
                    .font(.system(size: 11, weight: .semibold))
                Text("这是 macOS 的隐私保护，不是管理员权限。没有它，系统会拒绝移动 App 本体和其他 App 的沙盒容器。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("打开设置") { onOpenSettings() }
                .controlSize(.small)
            Button("重新检测") { onRecheck() }
                .controlSize(.small)
            Button("稍后") { onDismiss() }
                .controlSize(.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.orange.opacity(0.18)).frame(height: 0.5)
        }
    }
}

/// Explicit permission guide shown in the result sheet when TCC denied items.
struct PermissionResultCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.red)
                Text("macOS 拒绝了访问")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("应用本体和其他 App 的容器受系统隐私保护。请到 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中勾选“净卸”，然后完全退出并重新打开净卸再试。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("如果完全磁盘访问权限已开启仍然失败，请检查“应用管理”中是否允许净卸修改其他应用。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("打开完全磁盘访问权限") {
                    PermissionGuide.openFullDiskAccessSettings()
                }
                .controlSize(.small)
                Button("打开应用管理") {
                    PermissionGuide.openAppManagementSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.red.opacity(0.20), lineWidth: 0.5)
        )
    }
}
