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
