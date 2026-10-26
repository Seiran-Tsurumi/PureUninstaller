import Foundation
import AppKit

@MainActor
final class UninstallSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case uninstallerPrompt
        case scanning
        case preview
        case executing
        case result
    }

    @Published var isPresented = false
    @Published var phase: Phase = .idle
    @Published var mode: UninstallMode = .normal
    @Published var targets: [UninstallTarget] = []
    @Published var selectedPaths: Set<String> = []
    @Published var useTrash = true
    @Published var showFinalConfirmation = false
    @Published var result: UninstallResult?
    @Published var scanMessage = ""
    @Published var warnings: [String] = []
    @Published var processRecords: [ProcessManager.TerminationRecord] = []
    @Published var uninstallerCandidates: [UninstallerCandidate] = []
    @Published var lastLog: String?
    @Published var lastLogURL: URL?
    @Published var alertMessage: String?

    /// Called after deletion finishes so the main list can refresh.
    var onComplete: (() -> Void)?

    private var pendingApps: [AppInfo] = []
    private var isOrphanCleanup = false
    private var startedAt = Date()
    private var runID = UUID()

    var isExecuting: Bool { phase == .executing }

    var selectedCount: Int {
        let bodies = targets.filter { $0.appBody?.isDeletable == true }.count
        return bodies + targets.reduce(0) { $0 + topmostSelectedPaths(in: $1.residues).count }
    }

    var selectedSize: Int64 {
        var total: Int64 = 0
        for target in targets {
            if let body = target.appBody, body.isDeletable {
                total += body.size
            }
            total += topmostSelectedPaths(in: target.residues).reduce(Int64(0)) { $0 + $1.size }
        }
        return total
    }

    var deleteableAppBodies: Int {
        targets.filter { $0.appBody?.isDeletable == true }.count
    }

    /// App bodies that need the optional administrator path.
    var adminRemovalCount: Int {
        targets.filter { target in
            target.app?.requiresAdminRemoval == true && target.appBody?.isDeletable == true
        }.count
    }

    var lockedItemCount: Int {
        var count = 0
        for target in targets {
            if let body = target.appBody, !body.isDeletable { count += 1 }
            count += target.residues.filter { !$0.isSelectable }.count
        }
        return count
    }

    var windowTitle: String {
        if isOrphanCleanup { return "清理孤儿残留" }
        if targets.count == 1 { return "卸载 \(targets[0].title)" }
        return "批量卸载 \(targets.count) 个应用"
    }

    var confirmationMessage: String {
        let action = useTrash ? "移到废纸篓（可从废纸篓恢复）" : "永久删除（不可恢复）"
        let admin = adminRemovalCount > 0
            ? " 其中 \(adminRemovalCount) 个 root-owned 应用会请求管理员密码。"
            : ""
        return "将处理 \(selectedCount) 项，共 \(Fmt.size(selectedSize))，\(action)。\(admin)"
    }

    // MARK: - Entry points

    func beginUninstall(apps: [AppInfo], mode: UninstallMode) {
        guard phase != .executing else { return }
        let usable = apps.filter { $0.canBeUninstalled }
        guard !usable.isEmpty else {
            alertMessage = "选中的应用是系统应用或卸载器，不能卸载。"
            return
        }

        resetForNewSession()
        self.mode = mode
        pendingApps = usable
        isOrphanCleanup = false
        isPresented = true
        runID = UUID()

        if mode == .normal {
            let candidates = usable.compactMap { UninstallerLocator.find(for: $0) }
            if !candidates.isEmpty {
                uninstallerCandidates = candidates
                phase = .uninstallerPrompt
                return
            }
        }

        phase = .scanning
        scanMessage = "准备扫描…"
        Task { await prepare(runID: runID) }
    }

    func beginOrphanCleanup(groups: [OrphanGroup]) {
        guard phase != .executing, !groups.isEmpty else { return }
        resetForNewSession()
        runID = UUID()
        pendingApps = []
        isOrphanCleanup = true
        mode = .normal
        targets = groups.map { group in
            UninstallTarget(
                id: "orphan:" + group.id,
                title: group.displayName,
                subtitle: "\(group.confidence.title) · \(group.artifacts.count) 项",
                app: nil,
                appBody: nil,
                residues: group.artifacts,
                uninstaller: nil
            )
        }
        warnings = ["孤儿残留是启发式识别结果，已默认勾选，请逐项确认后再清理。"]
        selectAll()
        phase = .preview
        isPresented = true
    }

    func openUninstaller(_ candidate: UninstallerCandidate) {
        switch candidate.kind {
        case .application:
            NSWorkspace.shared.open(candidate.url)
        case .script:
            NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            alertMessage = "这是卸载脚本，为安全起见没有自动执行。请在 Finder 中确认后手动运行，完成后回到净卸继续。"
        }
    }

    func continueAfterUninstaller() {
        uninstallerCandidates = []
        phase = .scanning
        scanMessage = "准备扫描…"
        Task { await prepare(runID: runID) }
    }

    // MARK: - Scanning

    private func prepare(runID: UUID) async {
        guard runID == self.runID else { return }
        guard !pendingApps.isEmpty else {
            phase = .preview
            return
        }
        phase = .scanning
        warnings = []
        processRecords = []
        targets = []

        for app in pendingApps {
            scanMessage = "正在结束 \(app.name) 的关联进程…"
            let processes = await ProcessManager.processes(for: app)
            if !processes.isEmpty {
                let records = await ProcessManager.terminateAll(processes, force: mode == .force)
                processRecords.append(contentsOf: records)
                let failed = records.filter { !$0.success }
                if !failed.isEmpty {
                    warnings.append("\(app.name)：\(failed.count) 个进程未能结束，可改用强制卸载。")
                }
            }

            scanMessage = "正在扫描 \(app.name) 的残留…"
            guard runID == self.runID else { return }
            let target = await ResidueScanner.target(for: app, mode: mode)
            targets.append(target)
        }

        guard runID == self.runID else { return }

        if targets.contains(where: { $0.residues.isEmpty }) {
            warnings.append("部分应用没有发现用户库残留，仍会移除应用本体。")
        }
        if targets.contains(where: { $0.appBody?.isDeletable == false }) {
            warnings.append("部分应用本体所在目录不可写，将只清理残留；应用本体请在 Finder 中手动移除。")
        }
        scanMessage = ""
        selectAll()
        phase = .preview
    }

    // MARK: - Selection

    func selectAll() {
        var paths = Set<String>()
        for target in targets {
            for root in target.residues {
                paths.formUnion(selectablePaths(in: root))
            }
        }
        selectedPaths = paths
    }

    func selectNone() {
        selectedPaths.removeAll()
    }

    func setSelected(_ node: ResidueNode, selected: Bool) {
        guard node.isSelectable else { return }
        if selected {
            selectedPaths.formUnion(selectablePaths(in: node))
        } else {
            selectedPaths.subtract(selectablePaths(in: node))
            // If the user unchecks a child inside a selected directory, the
            // directory can no longer be deleted as a whole; keep only the
            // explicitly selected siblings.
            selectedPaths = selectedPaths.filter { !node.id.hasPrefix($0 + "/") }
        }
    }

    enum CheckState {
        case on
        case mixed
        case off
        case locked

        var symbol: String {
            switch self {
            case .on: return "checkmark.square.fill"
            case .mixed: return "minus.square.fill"
            case .off: return "square"
            case .locked: return "lock.square"
            }
        }
    }

    func checkState(for node: ResidueNode) -> CheckState {
        if node.isAppBody { return node.isDeletable ? .on : .locked }
        guard node.isSelectable else { return .locked }
        if selectedPaths.contains(node.id) { return .on }
        let prefix = node.id + "/"
        if selectedPaths.contains(where: { $0.hasPrefix(prefix) }) { return .mixed }
        return .off
    }

    // MARK: - Execution

    func execute() {
        guard phase == .preview else { return }
        guard selectedCount > 0 else {
            alertMessage = "没有选中任何可删除的项目。"
            return
        }

        phase = .executing
        scanMessage = "正在清理…"
        let deletionMode: DeletionMode = useTrash ? .trash : .permanent

        Task {
            // A process can restart while the preview is open; stop it again
            // immediately before deleting files.
            for target in targets {
                guard let app = target.app else { continue }
                let processes = await ProcessManager.processes(for: app)
                if !processes.isEmpty {
                    let records = await ProcessManager.terminateAll(processes, force: mode == .force)
                    processRecords.append(contentsOf: records)
                }
            }

            // Root-owned app bundles need the optional administrator path.
            let adminTargets = targets.filter { target in
                target.app?.requiresAdminRemoval == true && target.appBody?.isDeletable == true
            }
            let adminRequests = adminTargets.compactMap { target -> AdminRemovalService.Request? in
                guard let body = target.appBody else { return nil }
                return AdminRemovalService.Request(url: body.url, size: body.size)
            }

            var adminRecords: [DeletionRecord] = []
            if !adminRequests.isEmpty {
                scanMessage = "正在请求管理员权限…"
                adminRecords = await AdminRemovalService.remove(adminRequests, mode: deletionMode)
            }

            let adminPaths = Set(adminRequests.map { $0.url.path })
            let items = makeDeletionItems(excluding: adminPaths)
            // File deletion can walk large directory trees; keep it off the
            // main actor so the progress sheet stays responsive.
            let normalRecords = await Task.detached(priority: .userInitiated) {
                DeletionService.delete(items: items, mode: deletionMode)
            }.value
            let records = adminRecords + normalRecords
            let log = buildLog(items: items, records: normalRecords,
                               adminRecords: adminRecords, deletionMode: deletionMode)

            let success = records.filter(\.success)
            let failures = records.filter { !$0.success }
            let freed = deletionMode == .permanent ? success.reduce(Int64(0)) { $0 + $1.size } : 0
            let trashed = deletionMode == .trash ? success.reduce(Int64(0)) { $0 + $1.size } : 0
            let title: String
            if failures.isEmpty {
                title = isOrphanCleanup ? "残留清理完成" : "卸载完成"
            } else {
                title = "部分完成"
            }

            self.lastLog = log
            self.result = UninstallResult(
                title: title,
                deletedCount: success.count,
                failedCount: failures.count,
                freedBytes: freed,
                trashedBytes: trashed,
                records: records,
                logText: log,
                finishedAt: Date()
            )
            self.phase = .result
            self.scanMessage = ""
            self.onComplete?()
        }
    }

    func exportLastLog() {
        guard let lastLog else { return }
        let name: String
        if isOrphanCleanup {
            name = "Orphan-Cleanup-\(Fmt.shortDate(Date())).txt"
        } else if targets.count == 1 {
            name = LogExporter.defaultName(appName: targets[0].title)
        } else {
            name = "Uninstall-Batch-\(Fmt.shortDate(Date())).txt"
        }
        lastLogURL = LogExporter.export(text: lastLog, suggestedName: name)
    }

    func revealLastLog() {
        guard let lastLogURL else { return }
        LogExporter.reveal(lastLogURL)
    }

    func dismiss() {
        guard phase != .executing else { return }
        isPresented = false
        phase = .idle
        targets = []
        selectedPaths = []
        pendingApps = []
        uninstallerCandidates = []
        result = nil
        scanMessage = ""
        warnings = []
        processRecords = []
        isOrphanCleanup = false
    }

    func cancel() {
        guard phase != .executing else { return }
        isPresented = false
        resetForNewSession()
    }

    // MARK: - Private

    private func resetForNewSession() {
        runID = UUID()
        phase = .idle
        targets = []
        selectedPaths = []
        useTrash = true
        showFinalConfirmation = false
        result = nil
        scanMessage = ""
        warnings = []
        processRecords = []
        uninstallerCandidates = []
        alertMessage = nil
        lastLogURL = nil
        startedAt = Date()
    }

    private func selectablePaths(in node: ResidueNode) -> [String] {
        var paths: [String] = []
        if node.isSelectable { paths.append(node.id) }
        if let children = node.children {
            for child in children {
                paths.append(contentsOf: selectablePaths(in: child))
            }
        }
        return paths
    }

    private func topmostSelectedPaths(in roots: [ResidueNode]) -> [ResidueNode] {
        guard !selectedPaths.isEmpty else { return [] }
        var nodesByPath: [String: ResidueNode] = [:]
        func index(_ node: ResidueNode) {
            nodesByPath[node.id] = node
            node.children?.forEach(index)
        }
        roots.forEach(index)

        let rootPrefixes = roots.map { $0.id + "/" }
        let candidates = selectedPaths
            .filter { path in
                nodesByPath[path] != nil ||
                    rootPrefixes.contains(where: { path.hasPrefix($0) })
            }
            .sorted { $0.count < $1.count }

        var kept: [String] = []
        for path in candidates {
            if kept.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            kept.append(path)
        }
        return kept.compactMap { nodesByPath[$0] }
    }

    private func makeDeletionItems(excluding excluded: Set<String> = []) -> [DeletionService.Item] {
        var items: [DeletionService.Item] = []
        for target in targets {
            if let body = target.appBody, body.isDeletable, !excluded.contains(body.url.path) {
                items.append(DeletionService.Item(
                    url: body.url,
                    kind: .appBundle,
                    size: body.size,
                    label: "应用本体 — \(target.title)"
                ))
            }
            for node in topmostSelectedPaths(in: target.residues) {
                items.append(DeletionService.Item(
                    url: node.url,
                    kind: .residue,
                    size: node.size,
                    label: "\(node.category.title) — \(node.name)"
                ))
            }
        }
        return items
    }

    private func buildLog(
        items: [DeletionService.Item],
        records: [DeletionRecord],
        adminRecords: [DeletionRecord],
        deletionMode: DeletionMode
    ) -> String {
        var lines: [String] = []
        lines.append("净卸 — 卸载日志")
        lines.append("时间：\(Fmt.dateTime(startedAt)) — \(Fmt.dateTime(Date()))")
        lines.append("模式：\(isOrphanCleanup ? "孤儿残留清理" : mode.title)")
        lines.append("删除方式：\(deletionMode.title)")
        lines.append("")

        if isOrphanCleanup {
            lines.append("孤儿残留分组：")
            for target in targets {
                lines.append("  - \(target.title)  [\(target.subtitle)]")
            }
        } else {
            lines.append("应用：")
            for target in targets {
                guard let app = target.app else { continue }
                lines.append("  - \(app.name) \(app.versionDisplay)")
                lines.append("    路径：\(app.url.path)")
                lines.append("    Bundle ID：\(app.bundleID ?? "—")")
                lines.append("    来源：\(app.source.title)    大小：\(Fmt.size(app.size))")
            }
        }
        lines.append("")

        if !processRecords.isEmpty {
            lines.append("进程处理：")
            for record in processRecords {
                let status = record.success ? "成功" : "失败"
                lines.append("  [\(status)] PID \(record.process.pid) \(record.process.name) — \(record.message)")
            }
            lines.append("")
        }

        if !adminRecords.isEmpty {
            lines.append("管理员权限处理：")
            for record in adminRecords {
                let status = record.success ? "成功" : "失败"
                lines.append("  [\(status)] \(record.url.path)")
                lines.append("    \(Fmt.size(record.size)) — \(record.message)")
            }
            lines.append("")
        }

        lines.append("处理记录：")
        for (index, item) in items.enumerated() {
            let record = index < records.count ? records[index] : nil
            let result = record?.success == true ? "成功" : "失败"
            let message = record?.message ?? "未执行"
            lines.append("  [\(result)] \(item.label)")
            lines.append("    \(item.url.path)")
            lines.append("    \(Fmt.size(item.size)) — \(message)")
        }
        lines.append("")

        if !warnings.isEmpty {
            lines.append("提示：")
            warnings.forEach { lines.append("  - \($0)") }
            lines.append("")
        }

        let allRecords = adminRecords + records
        let success = allRecords.filter(\.success).count
        let failures = allRecords.count - success
        lines.append("汇总：成功 \(success) 项，失败 \(failures) 项")
        if allRecords.contains(where: { $0.isPermissionError }) {
            lines.append("注意：检测到 macOS 隐私权限拒绝。请授予“完全磁盘访问权限”后重新打开净卸再试。")
        }
        if deletionMode == .trash {
            let trashed = allRecords.filter(\.success).reduce(Int64(0)) { $0 + $1.size }
            lines.append("已移到废纸篓：\(Fmt.size(trashed))（清空废纸篓后释放空间）")
        } else {
            let freed = allRecords.filter(\.success).reduce(Int64(0)) { $0 + $1.size }
            lines.append("永久释放：\(Fmt.size(freed))")
        }
        lines.append("")
        if adminRecords.isEmpty {
            lines.append("未使用管理员权限，未修改 /System 或 SIP 状态。")
        } else {
            lines.append("管理员权限仅用于移动/删除选中的应用本体；未修改 /System 或 SIP 状态。")
        }
        return lines.joined(separator: "\n")
    }
}
