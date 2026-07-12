import Foundation
import AppKit
import Infrastructure
import AppCore

/// Opens applications through `NSWorkspace`.
struct WorkspaceApplicationOpener: ApplicationOpening {
    func openApplication(bundleIdentifier: String) async throws {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            throw CommandlyError.notFound("Application \(bundleIdentifier)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw CommandlyError.internalFailure("openApplication: \(error.localizedDescription)")
        }
    }
}

/// Discovers `.app` bundles under standard Applications directories.
///
/// Work runs off the main actor. Results are lightly cached in-process.
actor WorkspaceInstalledApplicationQuery: InstalledApplicationQuerying {
    private var cached: [InstalledApplication]?
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func installedApplications() async -> [InstalledApplication] {
        if let cached {
            return cached
        }
        let apps = Self.scan(fileManager: fileManager)
        cached = apps
        return apps
    }

    nonisolated private static func scan(fileManager: FileManager) -> [InstalledApplication] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        if let homeApps = Optional(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)) {
            roots.append(homeApps)
        }

        var byBundleID: [String: InstalledApplication] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url) else { continue }
                guard let bundleIdentifier = bundle.bundleIdentifier, bundleIdentifier.isEmpty == false else {
                    continue
                }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                byBundleID[bundleIdentifier] = InstalledApplication(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    path: url.path
                )
            }
        }
        return byBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
