import Foundation

/// Native allocated-size measurement, matching the number Finder reports.
enum FileSize {
    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey
    ]

    static func allocatedSize(of url: URL) -> Int64 {
        let standardized = url.standardizedFileURL
        guard let values = try? standardized.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }

        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: standardized,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: keys) else { continue }
            // Do not call `skipDescendants()` for symlinks: the enumerator
            // already does not follow them, and calling it can skip the rest of
            // the containing directory (which undercounted app sizes).
            if childValues.isSymbolicLink == true { continue }
            if childValues.isRegularFile == true {
                total += Int64(childValues.totalFileAllocatedSize ??
                               childValues.fileAllocatedSize ??
                               childValues.fileSize ?? 0)
            }
        }
        return total
    }

    static func allocatedSizes(of urls: [URL], concurrency: Int = 4) -> [URL: Int64] {
        guard !urls.isEmpty else { return [:] }
        var result: [URL: Int64] = [:]
        let lock = NSLock()
        let queue = DispatchQueue(label: "pureuninstaller.filesize", attributes: .concurrent)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: max(1, concurrency))

        for url in urls {
            group.enter()
            queue.async {
                semaphore.wait()
                let size = allocatedSize(of: url)
                lock.lock()
                result[url] = size
                lock.unlock()
                semaphore.signal()
                group.leave()
            }
        }
        group.wait()
        return result
    }

    static func lastModified(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
