import Foundation

/// Recursively builds the preview tree for one residue root.
enum ResidueTreeBuilder {
    static let maxNodes = 30_000

    static func build(
        url: URL,
        category: ResidueCategory,
        isAppBody: Bool = false,
        appSize: Int64? = nil,
        nodeBudget: inout Int,
        depth: Int = 0
    ) -> ResidueNode {
        let standardized = url.standardizedFileURL
        let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
        let requiresAdmin = SafetyGuard.requiresAdmin(standardized)
        let decision = SafetyGuard.validateDeletion(
            of: standardized,
            kind: isAppBody ? .appBundle : .residue
        )
        let deletable = isAppBody
            ? SafetyGuard.isAdminRemovableAppBundle(standardized)
            : decision.isAllowed
        let displayName = standardized.lastPathComponent.isEmpty
            ? standardized.path
            : standardized.lastPathComponent

        if isAppBody {
            return ResidueNode(
                id: standardized.path,
                url: standardized,
                name: displayName,
                size: appSize ?? FileSize.allocatedSize(of: standardized),
                isDirectory: true,
                category: .other,
                requiresAdmin: false,
                isDeletable: deletable,
                isAppBody: true,
                children: nil
            )
        }

        guard isDirectory else {
            let size = FileSize.allocatedSize(of: standardized)
            nodeBudget += 1
            return ResidueNode(
                id: standardized.path,
                url: standardized,
                name: displayName,
                size: size,
                isDirectory: false,
                category: category,
                requiresAdmin: requiresAdmin,
                isDeletable: deletable,
                isAppBody: false,
                children: nil
            )
        }

        guard depth < 16, nodeBudget < maxNodes else {
            nodeBudget += 1
            return ResidueNode(
                id: standardized.path,
                url: standardized,
                name: displayName,
                size: FileSize.allocatedSize(of: standardized),
                isDirectory: true,
                category: category,
                requiresAdmin: requiresAdmin,
                isDeletable: deletable,
                isAppBody: false,
                children: nil
            )
        }

        let childrenURLs = (try? FileManager.default.contentsOfDirectory(
            at: standardized,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )) ?? []

        var children: [ResidueNode] = []
        children.reserveCapacity(childrenURLs.count)
        for child in childrenURLs {
            if nodeBudget >= maxNodes { break }
            children.append(build(
                url: child,
                category: category,
                isAppBody: false,
                nodeBudget: &nodeBudget,
                depth: depth + 1
            ))
        }

        children.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return comparison == .orderedAscending
        }

        nodeBudget += 1
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        return ResidueNode(
            id: standardized.path,
            url: standardized,
            name: displayName,
            size: total,
            isDirectory: true,
            category: category,
            requiresAdmin: requiresAdmin,
            isDeletable: deletable,
            isAppBody: false,
            children: children.isEmpty ? nil : children
        )
    }

    static func appBody(for app: AppInfo) -> ResidueNode {
        var budget = 0
        return build(
            url: app.url,
            category: .other,
            isAppBody: true,
            appSize: app.size,
            nodeBudget: &budget
        )
    }
}
