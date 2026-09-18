import Foundation

/// Finder-only Automation state; querying without permission never sends a content event.
public enum FinderPathAuthorization: Sendable, Equatable {
    case authorized, requiresConsent, denied, finderUnavailable
}

/// The source reported by Finder for a copied POSIX path.
public enum FinderPathOrigin: Sendable, Equatable {
    case selectedItem, currentFolder
}

/// A short-lived, single-use read token. A path is text only and conveys no file-access grant.
public struct FinderPathSnapshot: Sendable, Equatable {
    public let id: UUID
    public let path: String
    public let origin: FinderPathOrigin
    public init(id: UUID, path: String, origin: FinderPathOrigin) {
        self.id = id; self.path = path; self.origin = origin
    }
}

/// Reads only after explicit command activation. Implementations never resolve or open source files.
public protocol FinderPathReading: Sendable {
    /// Only an explicit Allow action may pass true. macOS owns the resulting consent dialog.
    func authorization(allowPrompt: Bool) async throws -> FinderPathAuthorization
    /// One selected item, or the current folder when selection is empty. Several items are refused.
    func capture() async throws -> FinderPathSnapshot
    /// Consumes the token, checking the same Finder process/window/selection/path before copying.
    func validate(_ snapshot: FinderPathSnapshot) async throws
}

/// A synchronous main-actor commit lets the caller check cancellation immediately before writing.
@MainActor public protocol FinderPathCopying: Sendable {
    func copy(_ path: String) throws
}

/// User-safe failures intentionally omit file paths and raw Apple-event error strings.
public enum FinderPathError: Error, Sendable, Equatable, LocalizedError {
    case permissionRequired, permissionDenied, finderUnavailable, noWindow, multipleSelection
    case unsupportedLocation, invalidReply, changedContext, timedOut, unavailable, copyFailed, disabled, invalidRequest
    public var errorDescription: String? { message }
    public var message: String {
        switch self {
        case .permissionRequired: "Allow Finder access to copy its current path."
        case .permissionDenied: "Finder access is denied. In System Settings → Privacy & Security → Automation, enable Finder for Commandly, then retry."
        case .finderUnavailable: "Finder is not available. Open a Finder window, then retry."
        case .noWindow: "Open a Finder folder window, then retry. Desktop-only selection is not supported."
        case .multipleSelection: "Select just one item in Finder, or deselect everything to copy the current folder path."
        case .unsupportedLocation: "This Finder location does not provide a local file path. Open a regular folder or select one file, then retry."
        case .invalidReply: "Finder returned an unsupported or oversized response. Select one item in a regular folder, then retry."
        case .changedContext: "Finder changed while reading the path. Check its current selection and retry."
        case .timedOut: "Finder did not respond in time. Close any Finder dialog and retry."
        case .unavailable: "The Finder path could not be read. Open a regular Finder folder and retry."
        case .copyFailed: "The path could not be copied. Retry when the clipboard is available."
        case .disabled: "Finder Path is disabled in Commandly Settings."
        case .invalidRequest: "This Finder Path command is unavailable."
        }
    }
}
