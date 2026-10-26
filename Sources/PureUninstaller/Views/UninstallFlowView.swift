import SwiftUI
import AppKit

struct UninstallFlowView: View {
    @ObservedObject var session: UninstallSession

    var body: some View {
        Group {
            switch session.phase {
            case .uninstallerPrompt:
                UninstallerPromptView(session: session)
            case .scanning:
                ScanningView(session: session)
            case .preview:
                ResiduePreviewView(session: session)
            case .executing:
                ExecutingView(session: session)
            case .result:
                if let result = session.result {
                    UninstallResultView(session: session, result: result)
                } else {
                    EmptyView()
                }
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled(session.phase == .scanning || session.phase == .executing)
        .alert("提示", isPresented: sessionAlertBinding) {
            Button("好") { session.alertMessage = nil }
        } message: {
            Text(session.alertMessage ?? "")
        }
    }

    private var sessionAlertBinding: Binding<Bool> {
        Binding(
            get: { session.alertMessage != nil },
            set: { if !$0 { session.alertMessage = nil } }
        )
    }
}

// MARK: - Uninstaller prompt

struct UninstallerPromptView: View {
    @ObservedObject var session: UninstallSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("发现官方卸载器")
                        .font(.system(size: 16, weight: .semibold))
                    Text("建议先运行应用自带的卸载器，再让净卸清理用户库残留。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            DividerLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.uninstallerCandidates) { candidate in
                        HStack(spacing: 10) {
                            Image(systemName: candidate.kind == .application ? "app" : "terminal")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.appName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(candidate.url.path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(candidate.kind == .application ? "打开" : "在 Finder 中显示") {
                                session.openUninstaller(candidate)
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Text("打开卸载器后，请先完成它的流程，再回到这里点击“跳过并继续”。如果卸载器失败，可以直接继续，净卸仍会清理扫描到的用户库残留。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button("取消") { session.cancel() }
                Spacer()
                Button("跳过并继续") { session.continueAfterUninstaller() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 620, height: 430)
    }
}

// MARK: - Scanning

struct ScanningView: View {
    @ObservedObject var session: UninstallSession

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(session.scanMessage.isEmpty ? "正在扫描…" : session.scanMessage)
                .font(.system(size: 13, weight: .medium))
            Text("正在结束关联进程并扫描用户库，不会访问系统分区。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Button("取消") { session.cancel() }
                .padding(.top, 8)
        }
        .frame(width: 480, height: 280)
    }
}

// MARK: - Executing

struct ExecutingView: View {
    @ObservedObject var session: UninstallSession

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("正在清理…")
                .font(.system(size: 13, weight: .medium))
            Text("正在处理选中的文件，请勿关闭窗口。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 240)
    }
}

// MARK: - Preview

struct ResiduePreviewView: View {
    @ObservedObject var session: UninstallSession

    var body: some View {
        VStack(spacing: 0) {
            previewHeader
            DividerLine()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.targets) { target in
                        TargetSection(session: session, target: target)
                    }
                }
                .padding(16)
            }
            DividerLine()
            previewFooter
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert(confirmationTitle, isPresented: $session.showFinalConfirmation) {
            Button("取消", role: .cancel) {}
            Button(session.useTrash ? "移到废纸篓" : "永久删除", role: .destructive) {
                session.execute()
            }
        } message: {
            Text(session.confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        session.useTrash ? "确认移到废纸篓？" : "确认永久删除？"
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.useTrash ? "trash" : "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(session.useTrash ? Color.accentColor : Color.red)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.windowTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text("共 \(session.selectedCount) 项 · \(Fmt.size(session.selectedSize)) · 展开树形列表可逐项取消勾选")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.adminRemovalCount > 0 {
                Badge(text: "\(session.adminRemovalCount) 个需管理员", systemImage: "lock.shield", color: .orange)
            }
            if session.lockedItemCount > 0 {
                Badge(text: "\(session.lockedItemCount) 项已锁定", systemImage: "lock.fill", color: .secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var previewFooter: some View {
        VStack(spacing: 0) {
            if !session.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.warnings.enumerated()), id: \.offset) { _, warning in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            HStack(spacing: 10) {
                Button("全选") { session.selectAll() }
                    .controlSize(.small)
                Button("全不选") { session.selectNone() }
                    .controlSize(.small)

                Text("已选 \(session.selectedCount) 项 · \(Fmt.size(session.selectedSize))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(isOn: $session.useTrash) {
                    Text(session.useTrash ? "移到废纸篓" : "永久删除")
                        .font(.system(size: 11))
                        .foregroundStyle(session.useTrash ? Color.primary : Color.red)
                }
                .toggleStyle(.checkbox)
                .help("默认移到废纸篓，可恢复。取消勾选会永久删除，无法恢复。")

                Button("取消") { session.cancel() }
                Button {
                    session.showFinalConfirmation = true
                } label: {
                    Label(session.useTrash ? "移到废纸篓并清理" : "永久删除",
                          systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(session.useTrash ? .accentColor : .red)
                .disabled(session.selectedCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct TargetSection: View {
    @ObservedObject var session: UninstallSession
    let target: UninstallTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let app = target.app {
                    AppIconView(url: app.url, size: 20)
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                Text(target.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(target.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.size(target.totalSize))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                if let body = target.appBody {
                    ResidueRow(node: body, session: session, isAppBody: true)
                }
                if target.residues.isEmpty {
                    HStack {
                        Text("未发现用户库残留")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                } else {
                    OutlineGroup(target.residues, children: \.children) { node in
                        ResidueRow(node: node, session: session)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }
}

private struct ResidueRow: View {
    let node: ResidueNode
    @ObservedObject var session: UninstallSession
    var isAppBody: Bool = false
    private var _hovering = State<Bool>(wrappedValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    private var state: UninstallSession.CheckState {
        session.checkState(for: node)
    }

    var body: some View {
        HStack(spacing: 7) {
            TriStateCheckbox(state: state) {
                session.setSelected(node, selected: state == .off)
            }

            if isAppBody {
                AppIconView(url: node.url, size: 16)
            } else {
                Image(systemName: node.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(isAppBody ? "应用本体" : node.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if isAppBody && !FileManager.default.isWritableFile(atPath: node.url.path) {
                        Text("需管理员")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    if !isAppBody {
                        Text(node.category.title)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                        if node.risk >= .medium {
                            Text(node.risk.title)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(node.risk.color)
                        }
                    }
                    if node.requiresAdmin {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(node.url.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("在 Finder 中显示")
            }

            Text(Fmt.size(node.size))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(hovering ? Color.primary.opacity(0.035) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(node.url.path)
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }
    }
}
