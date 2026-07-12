import Foundation
import Darwin
import Infrastructure

/// Scans common support locations for files related to an installed application.
///
/// Uses the real user home (not the App Sandbox container home) so `~/Library`
/// support files are discovered the same way a desktop uninstaller would.
actor WorkspaceApplicationUninstallDiscoverer: ApplicationUninstallDiscovering {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func relatedItems(for application: InstalledApplication) async -> [ApplicationRelatedItem] {
        var byPath: [String: ApplicationRelatedItem] = [:]

        if let appItem = makeItem(atPath: application.path, forcedKind: .application) {
            byPath[appItem.path] = appItem
        }

        let library = realUserHomeDirectory().appendingPathComponent("Library", isDirectory: true)
        let needles = Self.matchNeedles(
            bundleIdentifier: application.bundleIdentifier,
            appName: application.name
        )

        let scanRoots: [URL] = [
            library.appendingPathComponent("Application Support", isDirectory: true),
            library.appendingPathComponent("Caches", isDirectory: true),
            library.appendingPathComponent("Preferences", isDirectory: true),
            library.appendingPathComponent("HTTPStorages", isDirectory: true),
            library.appendingPathComponent("Cookies", isDirectory: true),
            library.appendingPathComponent("WebKit", isDirectory: true),
            library.appendingPathComponent("Containers", isDirectory: true),
            library.appendingPathComponent("Group Containers", isDirectory: true),
            library.appendingPathComponent("Saved Application State", isDirectory: true),
            library.appendingPathComponent("LaunchAgents", isDirectory: true),
            library.appendingPathComponent("LaunchDaemons", isDirectory: true),
            library.appendingPathComponent("Logs", isDirectory: true),
            library.appendingPathComponent("Application Scripts", isDirectory: true),
            library.appendingPathComponent("PrivilegedHelperTools", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support", isDirectory: true),
            URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
            URL(fileURLWithPath: "/Library/PrivilegedHelperTools", isDirectory: true)
        ]

        for root in scanRoots {
            appendMatchingChildren(of: root, matching: needles, into: &byPath)
        }

        // Preferences often use the bare bundle id plus helper suffixes.
        appendMatchingChildren(
            of: library.appendingPathComponent("Preferences", isDirectory: true),
            matching: needles,
            into: &byPath
        )

        return byPath.values.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    /// Match tokens used against file/folder names (bundle id, helpers, app name).
    nonisolated static func matchNeedles(bundleIdentifier: String, appName: String) -> [String] {
        var needles: [String] = []
        let trimmedBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBundle.isEmpty == false {
            needles.append(trimmedBundle)
        }
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty == false {
            needles.append(trimmedName)
            needles.append(trimmedName.replacingOccurrences(of: " ", with: ""))
            needles.append(trimmedName.replacingOccurrences(of: " ", with: "-"))
            needles.append(trimmedName.replacingOccurrences(of: " ", with: "_"))
        }
        // Prefer longer needles first so matching stays specific.
        return Array(Set(needles))
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
    }

    /// Whether a file/folder name belongs to the application.
    nonisolated static func name(_ name: String, matchesNeedles needles: [String]) -> Bool {
        let lower = name.lowercased()
        for needle in needles {
            let token = needle.lowercased()
            if lower == token
                || lower.hasPrefix(token + ".")
                || lower.hasPrefix(token + "-")
                || lower.hasPrefix(token + "_")
                || lower.contains("." + token + ".")
                || lower.contains("." + token + "-")
                || lower.hasSuffix("." + token)
                || lower.hasSuffix("." + token + ".plist")
                || lower.hasSuffix("." + token + ".savedstate")
                || lower.hasSuffix("." + token + ".binarycookies")
            {
                return true
            }
            // App display-name folders ("ChatGPT Atlas", "ChatGPTAtlas").
            if token.contains(" ") == false,
               lower.contains(token),
               token.count >= 6 {
                return true
            }
            if token.contains(" "),
               lower.replacingOccurrences(of: " ", with: "").contains(token.replacingOccurrences(of: " ", with: "")) {
                return true
            }
        }
        return false
    }

    private func appendMatchingChildren(
        of directory: URL,
        matching needles: [String],
        into results: inout [String: ApplicationRelatedItem]
    ) {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .nameKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in contents {
            let name = child.lastPathComponent
            guard Self.name(name, matchesNeedles: needles) else { continue }
            if let item = makeItem(atPath: child.path, forcedKind: nil) {
                results[item.path] = item
            }
        }
    }

    private func makeItem(atPath path: String, forcedKind: ApplicationRelatedItemKind?) -> ApplicationRelatedItem? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        let url = URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
        let name = url.lastPathComponent
        let container = displayContainerPath(for: url.deletingLastPathComponent())
        let kind = forcedKind ?? inferredKind(name: name, isDirectory: isDirectory.boolValue)
        let size = byteCount(at: url, isDirectory: isDirectory.boolValue)
        return ApplicationRelatedItem(
            name: name,
            containerPath: container,
            path: path,
            byteCount: size,
            kind: kind
        )
    }

    private func inferredKind(name: String, isDirectory: Bool) -> ApplicationRelatedItemKind {
        let lower = name.lowercased()
        if lower.hasSuffix(".app") {
            return .application
        }
        if lower.hasSuffix(".plist") {
            return .preferences
        }
        return isDirectory ? .folder : .file
    }

    private func displayContainerPath(for url: URL) -> String {
        let home = realUserHomeDirectory().path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private func byteCount(at url: URL, isDirectory: Bool) -> Int64 {
        if isDirectory == false {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Real login-user home, bypassing the sandbox container home.
    private func realUserHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }
}
