import AppKit
import Infrastructure

/// AppKit adapter that freezes the current frontmost application for one command invocation.
@MainActor
final class WorkspaceFrontmostApplicationContextProvider:
    FrontmostApplicationContextProviding
{
    func snapshot() -> FrontmostApplicationContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApplicationContext(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName
        )
    }
}
