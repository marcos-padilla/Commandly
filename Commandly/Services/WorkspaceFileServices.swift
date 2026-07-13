import Foundation
import AppKit
import Infrastructure
import AppCore

/// Opens URLs through `NSWorkspace`.
struct WorkspaceURLOpener: URLOpening {
    func openURL(_ url: URL) async throws {
        let opened = NSWorkspace.shared.open(url)
        if opened == false {
            throw CommandlyError.internalFailure("Couldn’t open URL.")
        }
    }
}

/// Reveals files in Finder via `NSWorkspace`.
struct WorkspaceFileRevealer: FileRevealing {
    func revealInFinder(urls: [URL]) async throws {
        guard urls.isEmpty == false else {
            throw CommandlyError.invalidInput("No files to reveal.")
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// Native file actions backed by AppKit and coordinated filesystem operations.
@MainActor
final class WorkspaceFileActionService: FileActionServicing {
    private var applicationsByID: [String: URL] = [:]
    private var sharingServicesByID: [String: NSSharingService] = [:]

    func applications(toOpen url: URL) async -> [FileActionOption] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: url)
        applicationsByID = Dictionary(uniqueKeysWithValues: urls.map { ($0.path, $0) })
        return urls.map { applicationURL in
            FileActionOption(
                id: applicationURL.path,
                title: FileManager.default.displayName(atPath: applicationURL.path),
                subtitle: applicationURL.deletingLastPathComponent().path
            )
        }
    }

    func open(_ url: URL, withApplication optionID: String) async throws {
        guard let applicationURL = applicationsByID[optionID] else {
            throw CommandlyError.notFound("Application")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func share(_ url: URL, withService optionID: String) async throws {
        guard let service = sharingServicesByID[optionID], service.canPerform(withItems: [url]) else {
            throw CommandlyError.notFound("Sharing service")
        }
        service.perform(withItems: [url])
    }

    func chooseDestination(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    func duplicate(_ url: URL) async throws -> URL {
        try await performFileOperation { manager in
            let destination = Self.uniqueDestination(
                in: url.deletingLastPathComponent(),
                source: url,
                suffix: " copy",
                manager: manager
            )
            try manager.copyItem(at: url, to: destination)
            return destination
        }
    }

    func copy(_ url: URL, to directory: URL) async throws -> URL {
        try await performFileOperation { manager in
            let destination = Self.uniqueDestination(in: directory, source: url, manager: manager)
            try manager.copyItem(at: url, to: destination)
            return destination
        }
    }

    func move(_ url: URL, to directory: URL) async throws -> URL {
        try await performFileOperation { manager in
            let destination = Self.uniqueDestination(in: directory, source: url, manager: manager)
            try manager.moveItem(at: url, to: destination)
            return destination
        }
    }

    func createShortcut(for url: URL, in directory: URL) async throws -> URL {
        try await performFileOperation { manager in
            let baseName = "\(url.deletingPathExtension().lastPathComponent) Commandly Shortcut"
            var destination = directory.appendingPathComponent(baseName).appendingPathExtension("webloc")
            var index = 2
            while manager.fileExists(atPath: destination.path) {
                destination = directory
                    .appendingPathComponent("\(baseName) \(index)")
                    .appendingPathExtension("webloc")
                index += 1
            }
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["URL": url.absoluteString],
                format: .xml,
                options: 0
            )
            try data.write(to: destination, options: .atomic)
            return destination
        }
    }

    func moveToTrash(_ url: URL) async throws {
        _ = try await performFileOperation { manager in
            var destination: NSURL?
            try manager.trashItem(at: url, resultingItemURL: &destination)
            return destination as URL? ?? url
        }
    }

    private func performFileOperation(
        _ operation: @escaping @Sendable (FileManager) throws -> URL
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try operation(FileManager())
        }.value
    }

    private nonisolated static func uniqueDestination(
        in directory: URL,
        source: URL,
        suffix: String = "",
        manager: FileManager
    ) -> URL {
        let extensionName = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent + suffix
        var destination = directory.appendingPathComponent(stem)
        if extensionName.isEmpty == false {
            destination.appendPathExtension(extensionName)
        }
        var index = 2
        while manager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(stem) \(index)")
            if extensionName.isEmpty == false {
                destination.appendPathExtension(extensionName)
            }
            index += 1
        }
        return destination
    }
}

/// `sharingServices(forItems:)` is the only AppKit API that can populate Commandly's
/// explicitly requested nested sharing card. Apple deprecates custom share lists in favor
/// of its standard menu item, but the replacement cannot supply rows to custom UI.
@available(macOS, deprecated: 13)
extension WorkspaceFileActionService {
    func sharingServices(for url: URL) async -> [FileActionOption] {
        let services = NSSharingService.sharingServices(forItems: [url])
        sharingServicesByID = Dictionary(
            uniqueKeysWithValues: services.enumerated().map { index, service in
                ("share.\(index).\(service.title)", service)
            }
        )
        return sharingServicesByID.map { id, service in
            FileActionOption(id: id, title: service.title)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

/// Application-bundle helpers backed by `NSWorkspace` / file URLs.
struct WorkspaceApplicationBundleManager: ApplicationBundleManaging {
    private let urlOpener: any URLOpening

    init(urlOpener: any URLOpening = WorkspaceURLOpener()) {
        self.urlOpener = urlOpener
    }

    func showPackageContents(atApplicationPath path: String) async throws {
        let appURL = URL(fileURLWithPath: path, isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        guard FileManager.default.fileExists(atPath: contents.path) else {
            throw CommandlyError.notFound("Package contents")
        }
        try await urlOpener.openURL(contents)
    }

    func moveItemToTrash(atPath path: String) async throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CommandlyError.notFound("Item")
        }
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            throw CommandlyError.security("Couldn’t move that item to the Trash.")
        }
    }
}

/// Opens Finder Get Info via Apple Events.
struct FinderAppleScriptInfoPresenter: FinderInfoPresenting {
    func showGetInfo(atPath path: String) async throws {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            activate
            set theItem to (POSIX file "\(escaped)") as alias
            open information window of theItem
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CommandlyError.internalFailure("Couldn’t prepare Finder Get Info.")
        }
        _ = script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "Finder Get Info failed."
            throw CommandlyError.security(message)
        }
    }
}

/// Running-application introspection and terminate via AppKit.
struct WorkspaceRunningApplicationController: RunningApplicationControlling {
    func frontmostBundleIdentifier() async -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func runningApplications() async -> [RunningApplicationSnapshot] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleIdentifier = app.bundleIdentifier, bundleIdentifier.isEmpty == false else {
                return nil
            }
            guard app.activationPolicy == .regular else { return nil }
            return RunningApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                isActive: bundleIdentifier == frontmost
            )
        }
    }

    func terminate(bundleIdentifier: String) async -> Bool {
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }
        guard matches.isEmpty == false else { return false }
        var any = false
        for app in matches {
            if app.terminate() {
                any = true
            }
        }
        return any
    }
}
