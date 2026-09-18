import AppKit
import CoreServices
import Foundation

/// Typed failures from emptying the Trash.
nonisolated enum FinderTrashError: Error, Equatable, Sendable {
    case finderUnavailable
    /// The user has not allowed Commandly to control the Finder.
    case notAuthorized
    /// The Finder received the request and refused or failed it.
    case emptyFailed
}

/// Empties the Trash through the Finder.
nonisolated protocol FinderTrashEmptying: Sendable {
    func emptyTrash() async throws
}

/// Finder adapter for emptying the Trash.
///
/// A sandboxed app cannot delete another app's files itself, and there is no framework call for
/// "empty the Trash". The Finder owns the Trash, so Commandly asks it with one fixed Apple Event
/// — the same Finder authority Get Info and Finder Path already use, with no script text and no
/// caller-supplied event codes.
nonisolated struct FinderAppleEventTrashService: FinderTrashEmptying {
    private static let finderBundleIdentifier = "com.apple.finder"

    /// Codes from the installed Finder scripting definition and the public Apple Event headers.
    private enum Code {
        /// The Finder's own event suite.
        static let finderSuite: UInt32 = 0x666E6472 // fndr
        /// Its `empty` command.
        static let empty: UInt32 = 0x656D7074 // empt
        static let errorNumber: UInt32 = 0x6572726E // errn
    }

    /// Apple Event error numbers that mean consent, not a broken request.
    private static let notAuthorizedErrors: Set<Int> = [-1_743, -1_744]

    func emptyTrash() async throws {
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.finderBundleIdentifier
        ).first else {
            throw FinderTrashError.finderUnavailable
        }

        let processIdentifier = finder.processIdentifier

        // Emptying a full Trash can take a while, and the send blocks its thread until the Finder
        // replies, so it never runs on the main actor. The event and its reply stay inside the
        // task; only the reply's error number comes back out.
        let errorNumber = try await Task.detached(priority: .userInitiated) {
            let event = NSAppleEventDescriptor(
                eventClass: Code.finderSuite,
                eventID: Code.empty,
                targetDescriptor: NSAppleEventDescriptor(processIdentifier: processIdentifier),
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            let reply = try event.sendEvent(options: [.waitForReply], timeout: 120)
            return reply.paramDescriptor(forKeyword: Code.errorNumber)?.int32Value ?? 0
        }.value

        guard errorNumber == 0 else {
            throw Self.notAuthorizedErrors.contains(Int(errorNumber))
                ? FinderTrashError.notAuthorized
                : FinderTrashError.emptyFailed
        }
    }
}
