import Foundation
import Security

/// Reads bundle metadata, code-signing source and allocated size.
enum BundleInspector {
    static func inspect(url: URL, size: Int64? = nil) -> AppInfo? {
        let standardized = url.standardizedFileURL
        guard standardized.pathExtension.lowercased() == "app" else { return nil }

        let bundle = Bundle(url: standardized)
        let info = bundle?.infoDictionary ?? [:]
        let bundleID = info["CFBundleIdentifier"] as? String
        let rawName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? standardized.deletingPathExtension().lastPathComponent
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortVersion = (info["CFBundleShortVersionString"] as? String) ?? ""
        let build = (info["CFBundleVersion"] as? String) ?? ""
        let executable = info["CFBundleExecutable"] as? String

        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        let system = SafetyGuard.isSystemAppBundle(standardized) || SafetyGuard.isSystemAppBundle(resolved)
        let location: AppLocation
        if system {
            location = .system
        } else if SafetyGuard.isInside(standardized.path, SafetyGuard.home.appendingPathComponent("Applications").path) {
            location = .userApplications
        } else if SafetyGuard.isInside(standardized.path, "/Applications") {
            location = .applications
        } else {
            location = .other
        }

        let signing = signatureInfo(for: standardized)
        let source: AppSource
        if system {
            source = .appleSystem
        } else if hasAppStoreReceipt(standardized) {
            source = .appStore
        } else {
            source = signing.source
        }

        let uninstaller = isUninstallerBundle(name: name, bundleID: bundleID)
        let measuredSize = size ?? FileSize.allocatedSize(of: standardized)

        return AppInfo(
            id: standardized.path,
            url: standardized,
            name: name.isEmpty ? standardized.deletingPathExtension().lastPathComponent : name,
            bundleID: bundleID,
            version: shortVersion,
            build: build,
            size: measuredSize,
            source: source,
            location: location,
            isSystem: system,
            executableName: executable,
            teamID: signing.teamID,
            signingAuthority: signing.authority,
            isRunning: false,
            isUninstaller: uninstaller
        )
    }

    static func bundleID(at url: URL) -> String? {
        Bundle(url: url)?.infoDictionary?["CFBundleIdentifier"] as? String
    }

    static func hasAppStoreReceipt(_ url: URL) -> Bool {
        let receipt = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receipt.path)
    }

    private static func isUninstallerBundle(name: String, bundleID: String?) -> Bool {
        let lowered = name.lowercased()
        let id = (bundleID ?? "").lowercased()
        if lowered.contains("uninstall") || lowered.contains("卸载") {
            return id.contains("uninstall") || lowered.contains("uninstall")
        }
        return false
    }

    private static func signatureInfo(for url: URL) -> (source: AppSource, authority: String?, teamID: String?) {
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &code)
        guard createStatus == errSecSuccess, let code else {
            return (.unsigned, nil, nil)
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let status = SecCodeCopySigningInformation(code, flags, &information)
        guard status == errSecSuccess, let dictionary = information as? [String: Any] else {
            return (.unknown, nil, nil)
        }

        let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        var authority: String?
        if let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let first = certificates.first {
            authority = SecCertificateCopySubjectSummary(first) as String?
        }

        guard let authority else {
            return (.unsigned, nil, teamID)
        }
        if authority.contains("Developer ID Application") {
            return (.developerID, authority, teamID)
        }
        if authority.contains("Apple Mac OS Application Signing") ||
            authority.contains("Software Signing") {
            return (.appleSystem, authority, teamID)
        }
        if authority.contains("Apple Development") || authority.contains("Mac Developer") {
            return (.localSignature, authority, teamID)
        }
        return (.unknown, authority, teamID)
    }
}
