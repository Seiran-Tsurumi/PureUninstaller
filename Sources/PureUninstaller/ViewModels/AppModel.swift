import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case apps
        case orphans

        var id: String { rawValue }
        var title: String {
            switch self {
            case .apps: return "已安装应用"
            case .orphans: return "孤儿残留"
            }
        }
    }

    @Published var apps: [AppInfo] = []
    @Published var orphanGroups: [OrphanGroup] = []
    @Published var searchText = ""
    @Published var tab: Tab = .apps
    @Published var selectedAppIDs: Set<String> = []
    @Published var selectedOrphanIDs: Set<String> = []
    @Published var isLoadingApps = false
    @Published var isLoadingOrphans = false
    @Published var showLowConfidence = false
    @Published var errorMessage: String?
    @Published var orphanWarnings: [String] = []
    @Published var statusMessage: String?
    @Published var hasFullDiskAccess = false

    private var hasLoadedOrphans = false

    var filteredApps: [AppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(query) ||
            (app.bundleID?.localizedCaseInsensitiveContains(query) ?? false) ||
            app.url.path.localizedCaseInsensitiveContains(query) ||
            app.source.title.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredOrphans: [OrphanGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return orphanGroups.filter { group in
            if !showLowConfidence && group.confidence == .low { return false }
            guard !query.isEmpty else { return true }
            return group.displayName.localizedCaseInsensitiveContains(query) ||
                group.key.localizedCaseInsensitiveContains(query) ||
                group.artifacts.contains { $0.url.path.localizedCaseInsensitiveContains(query) }
        }
    }

    var selectedApps: [AppInfo] {
        apps.filter { selectedAppIDs.contains($0.id) && $0.canBeUninstalled }
    }

    var selectedOrphans: [OrphanGroup] {
        orphanGroups.filter { selectedOrphanIDs.contains($0.id) }
    }

    var selectableAppIDs: Set<String> {
        Set(apps.filter(\.canBeUninstalled).map(\.id))
    }

    var selectedAppSize: Int64 {
        selectedApps.reduce(0) { $0 + $1.size }
    }

    var selectedOrphanSize: Int64 {
        selectedOrphans.reduce(0) { $0 + $1.totalSize }
    }

    func loadApps() async {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        errorMessage = nil
        refreshPermissions()
        let scanned = await AppScanner.scan()
        let running = NSWorkspace.shared.runningApplications
        apps = scanned.map { app in
            var copy = app
            copy.isRunning = running.contains { runningApp in
                if let bundleID = copy.bundleID, runningApp.bundleIdentifier == bundleID { return true }
                if let path = runningApp.bundleURL?.standardizedFileURL.path {
                    return path == copy.url.path || SafetyGuard.isInside(path, copy.url.path)
                }
                return false
            }
            return copy
        }
        selectedAppIDs = selectedAppIDs.intersection(selectableAppIDs)
        isLoadingApps = false
        hasLoadedOrphans = false
        refreshPermissions()
        if tab == .orphans {
            await loadOrphans(force: true)
        }
    }

    func loadOrphans(force: Bool = false) async {
        guard !isLoadingOrphans else { return }
        if hasLoadedOrphans && !force { return }
        guard !apps.isEmpty else { return }
        isLoadingOrphans = true
        let result = await OrphanScanner.scan(installedApps: apps)
        orphanGroups = result.groups
        orphanWarnings = result.warnings
        selectedOrphanIDs = selectedOrphanIDs.intersection(Set(result.groups.map(\.id)))
        isLoadingOrphans = false
        hasLoadedOrphans = true
    }

    func reloadAll() async {
        // loadApps also refreshes the orphan list when that tab is active.
        await loadApps()
    }

    func refreshPermissions() {
        hasFullDiskAccess = PermissionGuide.hasFullDiskAccess()
    }

    func selectAllApps() {
        selectedAppIDs = selectableAppIDs
    }

    func clearAppSelection() {
        selectedAppIDs.removeAll()
    }

    func selectAllOrphans() {
        selectedOrphanIDs = Set(filteredOrphans.map(\.id))
    }

    func clearOrphanSelection() {
        selectedOrphanIDs.removeAll()
    }

    /// Select a dropped app, adding it to the list when it lives outside the
    /// standard scan roots. Returns nil for non-apps and system apps.
    func acceptDroppedApp(_ url: URL) -> AppInfo? {
        guard let inspected = AppScanner.inspectDropped(url: url) else {
            errorMessage = "请拖入一个 .app 应用包。"
            return nil
        }
        guard !inspected.isSystem else {
            errorMessage = "\(inspected.name) 是系统应用，受 SIP 保护，不能卸载。"
            return nil
        }
        guard !inspected.isUninstaller else {
            errorMessage = "这是卸载器，不是普通应用。"
            return nil
        }
        if inspected.url.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path ||
            inspected.bundleID == Bundle.main.bundleIdentifier ||
            inspected.bundleID == "com.pureuninstaller.app" {
            errorMessage = "不能卸载净卸自身。"
            return nil
        }
        var app = inspected
        app.isRunning = NSWorkspace.shared.runningApplications.contains { runningApp in
            runningApp.bundleIdentifier == app.bundleID ||
                runningApp.bundleURL?.standardizedFileURL.path == app.url.path
        }
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
        } else {
            apps.append(app)
            apps.sort { lhs, rhs in
                if lhs.isSystem != rhs.isSystem { return !lhs.isSystem }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        selectedAppIDs.insert(app.id)
        tab = .apps
        return app
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
