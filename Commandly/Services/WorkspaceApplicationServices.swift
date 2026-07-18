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
/// Work runs off the main actor. Results use a bounded in-process cache so installations and
/// removals become visible during a long-running process without rescanning on every query.
actor WorkspaceInstalledApplicationQuery: InstalledApplicationQuerying {
    typealias Scanner = @Sendable () -> [InstalledApplication]

    private struct CacheEntry {
        let applications: [InstalledApplication]
        let refreshedAt: Date
    }

    private let cacheLifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let scanner: Scanner
    private var cacheEntry: CacheEntry?

    init(
        cacheLifetime: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init,
        scanner: @escaping Scanner = WorkspaceInstalledApplicationQuery.scanWorkspace
    ) {
        self.cacheLifetime = max(0, cacheLifetime)
        self.now = now
        self.scanner = scanner
    }

    func installedApplications() async -> [InstalledApplication] {
        let currentDate = now()
        if let cacheEntry,
           Self.isFresh(
               cacheEntry.refreshedAt,
               at: currentDate,
               lifetime: cacheLifetime
           ) {
            return cacheEntry.applications
        }

        let applications = scanner()
        cacheEntry = CacheEntry(
            applications: applications,
            refreshedAt: now()
        )
        return applications
    }

    /// Forces the next query to rescan, for callers that already know application state changed.
    func invalidateCache() {
        cacheEntry = nil
    }

    nonisolated private static func isFresh(
        _ cachedAt: Date,
        at currentDate: Date,
        lifetime: TimeInterval
    ) -> Bool {
        let age = currentDate.timeIntervalSince(cachedAt)
        return age >= 0 && age < lifetime
    }

    nonisolated private static func scanWorkspace() -> [InstalledApplication] {
        scan(fileManager: .default)
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
