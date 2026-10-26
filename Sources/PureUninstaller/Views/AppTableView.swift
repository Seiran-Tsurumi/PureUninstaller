import SwiftUI
import AppKit

struct AppTableView: View {
    @ObservedObject var model: AppModel
    let onUninstall: (AppInfo, UninstallMode) -> Void
    let onShowProcesses: ([AppInfo]) -> Void

    private var selection: Binding<Set<String>> {
        Binding(
            get: { model.selectedAppIDs },
            set: { newValue in
                let allowed = newValue.filter { id in
                    model.apps.first(where: { $0.id == id })?.canBeUninstalled == true
                }
                model.selectedAppIDs = allowed
            }
        )
    }

    var body: some View {
        ZStack {
            Table(model.filteredApps, selection: selection) {
                TableColumn("") { app in
                    Button {
                        toggle(app)
                    } label: {
                        Image(systemName: model.selectedAppIDs.contains(app.id)
                              ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(app.canBeUninstalled
                                             ? (model.selectedAppIDs.contains(app.id) ? Color.accentColor : Color.secondary)
                                             : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!app.canBeUninstalled)
                    .help(app.isSystem ? "系统应用受 SIP 保护" : "选择")
                }
                .width(26)

                TableColumn("应用") { app in
                    HStack(spacing: 8) {
                        AppIconView(url: app.url, size: 22)
                            .opacity(app.isSystem ? 0.5 : 1)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(app.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if app.isSystem {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                } else if app.isRunning {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 5, height: 5)
                                        .help("正在运行")
                                }
                            }
                            Text(app.bundleID ?? "无 Bundle ID")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .opacity(app.isSystem ? 0.55 : 1)
                    .contextMenu { menu(for: app) }
                    .onTapGesture(count: 2) {
                        NSWorkspace.shared.activateFileViewerSelecting([app.url])
                    }
                }
                .width(min: 240, ideal: 300)

                TableColumn("版本") { app in
                    Text(app.versionDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(app.isSystem ? .secondary : .primary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110)

                TableColumn("大小") { app in
                    Text(Fmt.size(app.size))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(app.isSystem ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)

                TableColumn("来源") { app in
                    Text(app.source.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 105)

                TableColumn("状态") { app in
                    if app.isSystem {
                        Badge(text: "系统保护", systemImage: "lock.fill", color: .secondary)
                    } else if app.isRunning && !app.requiresAdminRemoval {
                        Badge(text: "运行中", systemImage: "circle.fill", color: .green)
                    } else if app.requiresAdminRemoval {
                        Badge(text: "需管理员", systemImage: "lock.shield", color: .orange)
                    } else {
                        Text("可卸载")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 78, ideal: 92)

                TableColumn("安装位置") { app in
                    Text(app.installLocationDisplay)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let app = model.apps.first(where: { $0.id == id }) {
                    menu(for: app)
                }
            }

            if model.isLoadingApps {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在扫描应用…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if model.filteredApps.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的应用",
                    message: "试试搜索名称、Bundle ID 或安装路径。"
                )
            }
        }
    }

    private func toggle(_ app: AppInfo) {
        guard app.canBeUninstalled else { return }
        if model.selectedAppIDs.contains(app.id) {
            model.selectedAppIDs.remove(app.id)
        } else {
            model.selectedAppIDs.insert(app.id)
        }
    }

    @ViewBuilder
    private func menu(for app: AppInfo) -> some View {
        if app.canBeUninstalled {
            Button("普通卸载…") { onUninstall(app, .normal) }
            Button("强制卸载…") { onUninstall(app, .force) }
            Divider()
            Button("查看关联进程") { onShowProcesses([app]) }
            Divider()
        } else {
            Text("系统应用受 SIP 保护")
        }
        Button("在 Finder 中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
        Button("复制 Bundle ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.bundleID ?? app.url.path, forType: .string)
        }
    }
}
