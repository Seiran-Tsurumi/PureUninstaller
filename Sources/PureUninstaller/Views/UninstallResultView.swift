import SwiftUI
import AppKit

struct UninstallResultView: View {
    @ObservedObject var session: UninstallSession
    let result: UninstallResult

    private var _showLog = State<Bool>(wrappedValue: false)
    private var showLog: Bool {
        get { _showLog.wrappedValue }
        nonmutating set { _showLog.wrappedValue = newValue }
    }
    private var showLogBinding: Binding<Bool> {
        Binding(get: { _showLog.wrappedValue }, set: { _showLog.wrappedValue = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            DividerLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if result.needsFullDiskAccess {
                        PermissionResultCard()
                    }
                    summary
                    if !result.failures.isEmpty {
                        failures
                    }
                    logSection
                }
                .padding(18)
            }
            DividerLine()
            footer
        }
        .frame(width: 760, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: result.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(result.failedCount == 0 ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                Text(Fmt.dateTime(result.finishedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Label("成功 \(result.deletedCount) 项", systemImage: "checkmark")
                    .foregroundStyle(.green)
                Label("失败 \(result.failedCount) 项", systemImage: "xmark")
                    .foregroundStyle(result.failedCount == 0 ? Color.secondary : Color.red)
                Spacer()
                if result.trashedBytes > 0 {
                    Text("已移到废纸篓 \(Fmt.size(result.trashedBytes))")
                        .foregroundStyle(.secondary)
                }
                if result.freedBytes > 0 {
                    Text("永久释放 \(Fmt.size(result.freedBytes))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))

            if result.trashedBytes > 0 {
                Text("移到废纸篓的项目会在清空废纸篓后释放空间。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var failures: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("失败项目")
                .font(.system(size: 12, weight: .semibold))
            ForEach(result.failures) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.url.path)
                        .font(.system(size: 9.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(record.message)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private var logSection: some View {
        DisclosureGroup(isExpanded: showLogBinding) {
            ScrollView {
                Text(result.logText)
                    .font(.system(size: 9.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 180)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        } label: {
            Text("查看清理日志")
                .font(.system(size: 11, weight: .medium))
        }
    }

    private var footer: some View {
        HStack {
            Button("导出日志") { session.exportLastLog() }
            if session.lastLogURL != nil {
                Button("在 Finder 中显示日志") { session.revealLastLog() }
            }
            Spacer()
            Button("完成") { session.dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
