import SwiftUI
import AppKit

struct OrphanTableView: View {
    @ObservedObject var model: AppModel
    let onCleanup: ([OrphanGroup]) -> Void

    private var selection: Binding<Set<String>> {
        Binding(
            get: { model.selectedOrphanIDs },
            set: { model.selectedOrphanIDs = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            banner
            DividerLine()
            ZStack {
                Table(model.filteredOrphans, selection: selection) {
                    TableColumn("") { group in
                        Button {
                            toggle(group)
                        } label: {
                            Image(systemName: model.selectedOrphanIDs.contains(group.id)
                                  ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13))
                                .foregroundStyle(model.selectedOrphanIDs.contains(group.id)
                                                 ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .width(26)

                    TableColumn("残留") { group in
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(group.key)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contextMenu {
                            Button("查看残留文件") {
                                if let first = group.artifacts.first {
                                    NSWorkspace.shared.activateFileViewerSelecting([first.url])
                                }
                            }
                            Button("清理这批残留…") { onCleanup([group]) }
                            Button("复制标识") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(group.key, forType: .string)
                            }
                        }
                    }
                    .width(min: 260, ideal: 340)

                    TableColumn("置信度") { group in
                        Badge(text: group.confidence.title,
                              systemImage: group.confidence.icon,
                              color: group.confidence.color)
                    }
                    .width(min: 75, ideal: 90)

                    TableColumn("大小") { group in
                        Text(Fmt.size(group.totalSize))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 70, ideal: 90)

                    TableColumn("文件数") { group in
                        Text(Fmt.number(group.fileCount))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 70)

                    TableColumn("最后修改") { group in
                        if let date = group.lastModified {
                            Text(Fmt.relativeDate(date))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .help(Fmt.dateTime(date))
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 80, ideal: 100)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))

                if model.isLoadingOrphans {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在分析孤儿残留…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else if model.filteredOrphans.isEmpty {
                    EmptyState(
                        icon: model.showLowConfidence ? "checkmark.seal" : "questionmark.folder",
                        title: "没有发现孤儿残留",
                        message: model.showLowConfidence
                            ? "用户库中没有找到与已删除应用相关的残留。"
                            : "没有中高置信度的残留。可以打开“显示低置信度”查看更多可疑项。"
                    )
                }
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("孤儿残留是根据用户库中的 Bundle ID、应用名和 LaunchAgent 启发式识别出来的。默认不勾选，请展开预览确认后再清理。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Toggle("显示低置信度", isOn: $model.showLowConfidence)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Button {
                Task { await model.loadOrphans(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新分析")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func toggle(_ group: OrphanGroup) {
        if model.selectedOrphanIDs.contains(group.id) {
            model.selectedOrphanIDs.remove(group.id)
        } else {
            model.selectedOrphanIDs.insert(group.id)
        }
    }
}
