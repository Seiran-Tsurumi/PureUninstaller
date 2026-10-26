import Foundation

/// Performs the final, user-confirmed deletion.
///
/// Every URL is validated again here. Nothing in this service resolves
/// symlinks to their targets, asks for admin rights, or touches a system path.
enum DeletionService {
    struct Item: Sendable {
        let url: URL
        let kind: SafetyGuard.Kind
        let size: Int64
        let label: String
    }

    static func delete(items: [Item], mode: DeletionMode) -> [DeletionRecord] {
        var records: [DeletionRecord] = []
        for item in items {
            let decision = SafetyGuard.validateDeletion(of: item.url, kind: item.kind)
            switch decision {
            case .refused(let reason):
                records.append(DeletionRecord(
                    url: item.url,
                    size: item.size,
                    success: false,
                    message: "已跳过：\(reason)"
                ))
                continue
            case .requiresAdmin:
                records.append(DeletionRecord(
                    url: item.url,
                    size: item.size,
                    success: false,
                    message: "已跳过：需要管理员权限，请手动删除"
                ))
                continue
            case .allowed:
                break
            }

            do {
                switch mode {
                case .trash:
                    do {
                        var resultingURL: NSURL?
                        try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                        records.append(DeletionRecord(
                            url: item.url,
                            size: item.size,
                            success: true,
                            message: "已移到废纸篓"
                        ))
                    } catch {
                        // Compatibility path for root-owned app bundles: rename
                        // into ~/.Trash instead of asking Finder for Put Back
                        // metadata. The item remains recoverable.
                        do {
                            _ = try TrashMover.moveToTrash(item.url)
                            records.append(DeletionRecord(
                                url: item.url,
                                size: item.size,
                                success: true,
                                message: "已移到废纸篓（兼容模式，可从废纸篓手动拖回）"
                            ))
                        } catch let fallbackError {
                            let ns = fallbackError as NSError
                            let writable = FileManager.default.isWritableFile(atPath: item.url.path)
                            let message: String
                            if !writable {
                                message = "失败：应用本体属于 root，普通用户不能删除。请改用“移到废纸篓”或在 Finder 中用管理员权限删除。 [\(ns.domain) \(ns.code)]"
                            } else {
                                message = PermissionGuide.message(for: fallbackError)
                            }
                            records.append(DeletionRecord(
                                url: item.url,
                                size: item.size,
                                success: false,
                                message: message,
                                isPermissionError: writable && PermissionGuide.isPermissionError(fallbackError)
                            ))
                        }
                    }
                case .permanent:
                    // Permanent recursive deletion of a root-owned bundle is
                    // not possible without admin rights. Fail clearly instead of
                    // partially removing files.
                    if case .appBundle = item.kind,
                       !FileManager.default.isWritableFile(atPath: item.url.path) {
                        records.append(DeletionRecord(
                            url: item.url,
                            size: item.size,
                            success: false,
                            message: "失败：应用本体属于 root，永久删除需要管理员权限。请把删除方式改为“移到废纸篓”，或在 Finder 中用管理员权限删除。",
                            isPermissionError: false
                        ))
                        continue
                    }
                    try FileManager.default.removeItem(at: item.url)
                    records.append(DeletionRecord(
                        url: item.url,
                        size: item.size,
                        success: true,
                        message: "已永久删除"
                    ))
                }
            } catch {
                let denied = PermissionGuide.isPermissionError(error)
                records.append(DeletionRecord(
                    url: item.url,
                    size: item.size,
                    success: false,
                    message: PermissionGuide.message(for: error),
                    isPermissionError: denied
                ))
            }
        }
        return records
    }
}
