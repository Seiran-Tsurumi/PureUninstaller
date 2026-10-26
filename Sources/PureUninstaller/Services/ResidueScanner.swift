import Foundation

/// Scans the standard macOS residue locations for one app.
enum ResidueScanner {
    struct Result {
        let roots: [ResidueNode]
        let warnings: [String]
    }

    private struct RootSpec {
        let url: URL
        let category: ResidueCategory
        /// When true, inspect immediate children of an unmatched vendor folder
        /// (for example `Application Support/Google/Chrome`).
        let inspectOneLevel: Bool
    }

    private struct Candidate {
        let url: URL
        let category: ResidueCategory
        let requiresAdmin: Bool
    }

    static func scan(app: AppInfo) async -> Result {
        guard !app.isSystem else {
            return Result(roots: [], warnings: ["系统应用受 SIP 保护，已跳过残留扫描。"])
        }

        return await Task.detached(priority: .userInitiated) {
            scanSync(app: app)
        }.value
    }

    private static func scanSync(app: AppInfo) -> Result {
        let matcher = AppMatcher(app: app)
        let specs = rootSpecs()
        var candidates: [Candidate] = []
        var warnings: [String] = []

        for spec in specs {
            guard FileManager.default.fileExists(atPath: spec.url.path) else { continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: spec.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )) ?? []

            for child in children {
                let name = artifactName(for: child, category: spec.category)
                if matches(name: name, url: child, category: spec.category, matcher: matcher) {
                    candidates.append(Candidate(
                        url: child,
                        category: spec.category,
                        requiresAdmin: SafetyGuard.requiresAdmin(child)
                    ))
                    if spec.category == .launchAgents || spec.category == .launchDaemons,
                       let helper = helperPath(in: child), !candidates.contains(where: { $0.url == helper }) {
                        candidates.append(Candidate(
                            url: helper,
                            category: .other,
                            requiresAdmin: SafetyGuard.requiresAdmin(helper)
                        ))
                    }
                } else if spec.inspectOneLevel {
                    let grandchildren = (try? FileManager.default.contentsOfDirectory(
                        at: child,
                        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                        options: []
                    )) ?? []
                    for grandchild in grandchildren {
                        let nestedName = artifactName(for: grandchild, category: spec.category)
                        if matchesNested(name: nestedName, url: grandchild, matcher: matcher) {
                            candidates.append(Candidate(
                                url: grandchild,
                                category: spec.category,
                                requiresAdmin: SafetyGuard.requiresAdmin(grandchild)
                            ))
                        }
                    }
                }
            }
        }

        // Remove protected/unreadable roots and nested duplicates: if a parent
        // is already selected, its children are represented inside its tree.
        candidates = candidates.filter { !SafetyGuard.isSystemPath($0.url) }
        candidates.sort { $0.url.path.count < $1.url.path.count }
        var kept: [Candidate] = []
        for candidate in candidates {
            let path = candidate.url.standardizedFileURL.path
            let covered = kept.contains { parent in
                SafetyGuard.isInside(path, parent.url.standardizedFileURL.path)
            }
            if !covered { kept.append(candidate) }
        }

        var budget = 0
        var roots: [ResidueNode] = []
        for candidate in kept {
            let node = ResidueTreeBuilder.build(
                url: candidate.url,
                category: candidate.category,
                nodeBudget: &budget
            )
            roots.append(node)
        }

        roots.sort { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk > rhs.risk }
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        if roots.isEmpty {
            warnings.append("没有在用户库中发现可清理的残留。")
        }
        if budget >= ResidueTreeBuilder.maxNodes {
            warnings.append("残留文件数量超过显示上限，剩余内容会随所属目录一起删除。")
        }

        return Result(roots: roots, warnings: warnings)
    }

    /// Build a complete uninstall target for the preview sheet.
    static func target(for app: AppInfo, mode: UninstallMode) async -> UninstallTarget {
        let result = await scan(app: app)
        let uninstaller = mode == .normal ? UninstallerLocator.find(for: app) : nil
        return UninstallTarget(
            id: app.id,
            title: app.name,
            subtitle: app.versionDisplay,
            app: app,
            appBody: app.canBeUninstalled ? ResidueTreeBuilder.appBody(for: app) : nil,
            residues: result.roots,
            uninstaller: uninstaller
        )
    }

    // MARK: - Roots

    private static func rootSpecs() -> [RootSpec] {
        let home = SafetyGuard.home
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var specs: [RootSpec] = [
            RootSpec(url: library.appendingPathComponent("Preferences"), category: .preferences, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Preferences/ByHost"), category: .preferences, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Caches"), category: .caches, inspectOneLevel: true),
            RootSpec(url: library.appendingPathComponent("Application Support"), category: .applicationSupport, inspectOneLevel: true),
            RootSpec(url: library.appendingPathComponent("Logs"), category: .logs, inspectOneLevel: true),
            RootSpec(url: library.appendingPathComponent("LaunchAgents"), category: .launchAgents, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Containers"), category: .containers, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Group Containers"), category: .groupContainers, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Application Scripts"), category: .applicationScripts, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("HTTPStorages"), category: .httpStorages, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("WebKit"), category: .webKit, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Saved Application State"), category: .savedState, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Cookies"), category: .cookies, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Application Support/CrashReporter"), category: .crashReports, inspectOneLevel: false),
            RootSpec(url: library.appendingPathComponent("Logs/DiagnosticReports"), category: .crashReports, inspectOneLevel: false)
        ]

        let pluginPaths = [
            "Internet Plug-Ins",
            "Audio/Plug-Ins",
            "Frameworks",
            "QuickLook",
            "Spotlight",
            "Screen Savers",
            "PreferencePanes",
            "Services",
            "Input Methods",
            "Workflow"
        ]
        for path in pluginPaths {
            specs.append(RootSpec(url: library.appendingPathComponent(path), category: .plugins, inspectOneLevel: false))
        }

        // Root-level launchd items are read-only for this app. They are shown so
        // the user can remove them manually with the correct privileges.
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/Application Support"), category: .applicationSupport, inspectOneLevel: true))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/Caches"), category: .caches, inspectOneLevel: true))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/Preferences"), category: .preferences, inspectOneLevel: false))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/Logs"), category: .logs, inspectOneLevel: true))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), category: .launchDaemons, inspectOneLevel: false))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/LaunchAgents"), category: .launchAgents, inspectOneLevel: false))
        specs.append(RootSpec(url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), category: .other, inspectOneLevel: false))

        return specs
    }

    // MARK: - Matching

    private static func artifactName(for url: URL, category: ResidueCategory) -> String {
        switch category {
        case .preferences, .launchAgents, .launchDaemons, .crashReports:
            return url.deletingPathExtension().lastPathComponent
        case .savedState:
            let name = url.lastPathComponent
            return name.hasSuffix(".savedState") ? String(name.dropLast(".savedState".count)) : name
        case .httpStorages, .cookies:
            let name = url.lastPathComponent
            return name.hasSuffix(".binarycookies") ? String(name.dropLast(".binarycookies".count)) : name
        default:
            return url.lastPathComponent
        }
    }

    private static func matches(
        name: String,
        url: URL,
        category: ResidueCategory,
        matcher: AppMatcher
    ) -> Bool {
        switch category {
        case .launchAgents, .launchDaemons:
            let dictionary = PlistReader.dictionary(at: url)
            if let dictionary {
                return matcher.matchesLaunchdPlist(name: name, contents: dictionary)
            }
            return matcher.matchesIdentifier(name) || matcher.matchesName(name)
        case .plugins:
            if matcher.matchesIdentifier(name) || matcher.matchesName(name) { return true }
            if let bundleID = BundleInspector.bundleID(at: url) {
                return matcher.matchesIdentifier(bundleID)
            }
            return false
        case .crashReports:
            let normalized = BundleMatcher.normalizeName(name)
            let appKey = BundleMatcher.normalizeName(matcher.appName)
            if appKey.count >= 3, normalized.hasPrefix(appKey) { return true }
            return matcher.matchesIdentifier(name) || matcher.matchesName(name)
        default:
            return matcher.matchesIdentifier(name) || matcher.matchesName(name)
        }
    }

    private static func matchesNested(name: String, url: URL, matcher: AppMatcher) -> Bool {
        if matcher.matchesNestedName(name) { return true }
        if let bundleID = BundleInspector.bundleID(at: url), matcher.matchesIdentifier(bundleID) {
            return true
        }
        return false
    }

    /// `Program` / `ProgramArguments` sometimes point at a privileged helper.
    private static func helperPath(in plistURL: URL) -> URL? {
        guard let dictionary = PlistReader.dictionary(at: plistURL) else { return nil }
        if let program = dictionary["Program"] as? String {
            let url = URL(fileURLWithPath: program)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let arguments = dictionary["ProgramArguments"] as? [String],
           let first = arguments.first {
            let url = URL(fileURLWithPath: first)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

enum PlistReader {
    static func dictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return object as? [String: Any]
    }
}
