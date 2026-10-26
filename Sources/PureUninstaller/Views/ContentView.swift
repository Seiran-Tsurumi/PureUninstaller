import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @StateObject private var model = AppModel()
    @StateObject private var session = UninstallSession()

    // See Components.swift: these are the raw `State` wrappers that the
    // `@State` macro would synthesize, for toolchains without SwiftUIMacros.
    private var _uninstallMode = State<UninstallMode>(wrappedValue: .normal)
    private var _showProcesses = State<Bool>(wrappedValue: false)
    private var _processApps = State<[AppInfo]>(wrappedValue: [])
    private var _showAbout = State<Bool>(wrappedValue: false)
    private var _isDropTargeted = State<Bool>(wrappedValue: false)
    private var _permissionBannerDismissed = State<Bool>(wrappedValue: false)
    private var _showPermissionDialog = State<Bool>(wrappedValue: false)
    private var _pendingUninstall = State<(() -> Void)?>(wrappedValue: nil)

    private var uninstallMode: UninstallMode {
        get { _uninstallMode.wrappedValue }
        nonmutating set { _uninstallMode.wrappedValue = newValue }
    }
    private var processApps: [AppInfo] {
        get { _processApps.wrappedValue }
        nonmutating set { _processApps.wrappedValue = newValue }
    }
    private var showProcesses: Bool {
        get { _showProcesses.wrappedValue }
        nonmutating set { _showProcesses.wrappedValue = newValue }
    }
    private var showAbout: Bool {
        get { _showAbout.wrappedValue }
        nonmutating set { _showAbout.wrappedValue = newValue }
    }
    private var isDropTargeted: Bool {
        get { _isDropTargeted.wrappedValue }
        nonmutating set { _isDropTargeted.wrappedValue = newValue }
    }
    private var permissionBannerDismissed: Bool {
        get { _permissionBannerDismissed.wrappedValue }
        nonmutating set { _permissionBannerDismissed.wrappedValue = newValue }
    }
    private var showPermissionDialog: Bool {
        get { _showPermissionDialog.wrappedValue }
        nonmutating set { _showPermissionDialog.wrappedValue = newValue }
    }
    private var pendingUninstall: (() -> Void)? {
        get { _pendingUninstall.wrappedValue }
        nonmutating set { _pendingUninstall.wrappedValue = newValue }
    }
    private var permissionDialogBinding: Binding<Bool> {
        Binding(get: { _showPermissionDialog.wrappedValue }, set: { _showPermissionDialog.wrappedValue = $0 })
    }
    private var uninstallModeBinding: Binding<UninstallMode> {
        Binding(get: { _uninstallMode.wrappedValue }, set: { _uninstallMode.wrappedValue = $0 })
    }
    private var showProcessesBinding: Binding<Bool> {
        Binding(get: { _showProcesses.wrappedValue }, set: { _showProcesses.wrappedValue = $0 })
    }
    private var showAboutBinding: Binding<Bool> {
        Binding(get: { _showAbout.wrappedValue }, set: { _showAbout.wrappedValue = $0 })
    }
    private var dropTargetedBinding: Binding<Bool> {
        Binding(get: { _isDropTargeted.wrappedValue }, set: { _isDropTargeted.wrappedValue = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            DividerLine()
            if !model.hasFullDiskAccess && !permissionBannerDismissed {
                PermissionBanner(
                    onOpenSettings: { PermissionGuide.openFullDiskAccessSettings() },
                    onRecheck: { model.refreshPermissions() },
                    onDismiss: { permissionBannerDismissed = true }
                )
                DividerLine()
            }
            content
            DividerLine()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1080, minHeight: 640)
        .sheet(isPresented: $session.isPresented) {
            UninstallFlowView(session: session)
                .frame(width: 980, height: 700)
        }
        .sheet(isPresented: showProcessesBinding) {
            ProcessListView(apps: processApps)
        }
        .sheet(isPresented: showAboutBinding) {
            AboutView()
        }
        .confirmationDialog(
            "需要完全磁盘访问权限",
            isPresented: permissionDialogBinding,
            titleVisibility: .visible
        ) {
            Button("打开设置") {
                pendingUninstall = nil
                PermissionGuide.openFullDiskAccessSettings()
            }
            Button("仍要尝试", role: .destructive) {
                let action = pendingUninstall
                pendingUninstall = nil
                action?()
            }
            Button("取消", role: .cancel) {
                pendingUninstall = nil
            }
        } message: {
            Text("macOS 会拒绝移动 App 本体和其他 App 的容器。请授予“完全磁盘访问权限”后，完全退出并重新打开净卸。")
        }
        .alert("提示", isPresented: alertBinding) {
            Button("好") {
                session.alertMessage = nil
                model.errorMessage = nil
            }
        } message: {
            Text(currentAlertText ?? "")
        }
        .onDrop(of: [UTType.fileURL], isTargeted: dropTargetedBinding) { providers in
            handleDrop(providers)
        }
        .overlay { dropOverlay }
        .task {
            session.onComplete = {
                Task { await model.reloadAll() }
            }
            model.refreshPermissions()
            if model.apps.isEmpty {
                await model.loadApps()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
        .onChange(of: model.tab) { _, newValue in
            if newValue == .orphans {
                Task { await model.loadOrphans() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("净卸")
                    .font(.system(size: 17, weight: .semibold))
                Text("应用卸载与残留清理 · 只动应用本体与用户库")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Picker("", selection: $model.tab) {
                Text("已安装 \(model.apps.count)").tag(AppModel.Tab.apps)
                Text("孤儿残留 \(model.orphanGroups.count)").tag(AppModel.Tab.orphans)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)

            SearchBox(
                text: $model.searchText,
                placeholder: model.tab == .apps ? "搜索应用、Bundle ID 或路径" : "搜索残留名称或路径"
            )

            Menu {
                if model.tab == .apps {
                    Button("全选可卸载应用") { model.selectAllApps() }
                    Button("取消选择") { model.clearAppSelection() }
                } else {
                    Button("全选当前结果") { model.selectAllOrphans() }
                    Button("取消选择") { model.clearOrphanSelection() }
                }
            } label: {
                Image(systemName: "checklist")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("选择")

            Button {
                Task { await model.reloadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新扫描")

            Button {
                PermissionGuide.openFullDiskAccessSettings()
            } label: {
                Image(systemName: model.hasFullDiskAccess ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(model.hasFullDiskAccess ? Color.green : Color.orange)
            }
            .buttonStyle(.borderless)
            .help(model.hasFullDiskAccess
                  ? "完全磁盘访问权限：已开启（点击打开设置）"
                  : "完全磁盘访问权限：未开启（点击打开设置）")

            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("关于净卸")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .apps:
            AppTableView(
                model: model,
                onUninstall: { app, mode in
                    uninstallMode = mode
                    startUninstall(apps: [app], mode: mode)
                },
                onShowProcesses: { apps in
                    processApps = apps
                    showProcesses = true
                }
            )
        case .orphans:
            OrphanTableView(
                model: model,
                onCleanup: { groups in
                    session.beginOrphanCleanup(groups: groups)
                }
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(summaryText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if model.tab == .apps {
                Picker("", selection: uninstallModeBinding) {
                    Text("普通").tag(UninstallMode.normal)
                    Text("强制").tag(UninstallMode.force)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 108)
                .help("普通卸载会优先打开官方卸载器；强制卸载跳过并强制结束进程。")

                Button("查看进程") {
                    processApps = model.selectedApps
                    showProcesses = true
                }
                .disabled(model.selectedApps.isEmpty)
                .help("查看选中应用的关联进程")

                Button("导出日志") {
                    session.exportLastLog()
                }
                .disabled(session.lastLog == nil)
                .help("导出上一次卸载日志")

                Button {
                    startUninstall(apps: model.selectedApps, mode: uninstallMode)
                } label: {
                    Label(uninstallMode == .force ? "强制卸载" : "卸载选中", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(uninstallMode == .force ? .red : .accentColor)
                .disabled(model.selectedApps.isEmpty)
            } else {
                Button("查看文件") {
                    if let group = model.selectedOrphans.first, let first = group.artifacts.first {
                        NSWorkspace.shared.activateFileViewerSelecting([first.url])
                    }
                }
                .disabled(model.selectedOrphans.isEmpty)

                Button("导出日志") {
                    session.exportLastLog()
                }
                .disabled(session.lastLog == nil)

                Button {
                    session.beginOrphanCleanup(groups: model.selectedOrphans)
                } label: {
                    Label("清理选中残留", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.selectedOrphans.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var summaryText: String {
        switch model.tab {
        case .apps:
            let count = model.apps.count
            let selected = model.selectedApps.count
            return "共 \(count) 个应用 · 已选 \(selected) 个 · \(Fmt.size(model.selectedAppSize))"
        case .orphans:
            let count = model.orphanGroups.count
            let selected = model.selectedOrphans.count
            return "共 \(count) 个候选 · 已选 \(selected) 个 · \(Fmt.size(model.selectedOrphanSize))"
        }
    }

    // MARK: - Drag & drop

    private var dropOverlay: some View {
        Group {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(8)
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.app")
                            .font(.system(size: 24, weight: .light))
                        Text("松开以分析应用")
                            .font(.system(size: 12, weight: .medium))
                        Text("支持 .app 应用包")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            }
            guard let url else { return }
            DispatchQueue.main.async {
                if let app = model.acceptDroppedApp(url) {
                    uninstallMode = .normal
                    startUninstall(apps: [app], mode: .normal)
                }
            }
        }
        return true
    }

    /// Gate the actual uninstall behind the Full Disk Access explanation.
    /// The user can still choose “仍要尝试” for a residue-only attempt.
    private func startUninstall(apps: [AppInfo], mode: UninstallMode) {
        guard !apps.isEmpty else { return }
        if model.hasFullDiskAccess {
            session.beginUninstall(apps: apps, mode: mode)
            return
        }
        pendingUninstall = { [weak session] in
            session?.beginUninstall(apps: apps, mode: mode)
        }
        showPermissionDialog = true
    }

    // MARK: - Alerts

    private var currentAlertText: String? {
        if let error = model.errorMessage { return error }
        // While the sheet is open, `UninstallFlowView` owns session alerts.
        if !session.isPresented, let alert = session.alertMessage { return alert }
        return nil
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { currentAlertText != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                    if !session.isPresented { session.alertMessage = nil }
                }
            }
        )
    }
}
