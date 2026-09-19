import CommandKit
import Foundation
import Infrastructure
import ModuleKit

/// Output names produced by the module's commands.
public enum ClipboardToolsOutputName {
    /// Whether the command changed the clipboard.
    public static let didChange = "didChange"
    /// How many tracking parameters were removed.
    public static let removedParameterCount = "removedParameterCount"
}

/// The module's clipboard operations.
///
/// Every command and any UI action goes through this one type, so there is a single implementation
/// of each operation. It performs no presentation and returns no clipboard content to its caller.
@MainActor
public struct ClipboardToolsOperations {
    private let pasteboard: any PasteboardAccessing
    private let clearing: any PasteboardClearing
    private let makeCleaner: @MainActor () -> TrackingParameterCleaner

    /// Creates the operations.
    ///
    /// - Parameter makeCleaner: builds a cleaner from current settings, so a change to the user's
    ///   extra parameter list takes effect without rebuilding the module.
    public init(
        pasteboard: any PasteboardAccessing,
        clearing: any PasteboardClearing,
        makeCleaner: @escaping @MainActor () -> TrackingParameterCleaner = { TrackingParameterCleaner() }
    ) {
        self.pasteboard = pasteboard
        self.clearing = clearing
        self.makeCleaner = makeCleaner
    }

    /// Replaces rich clipboard text with its plain text.
    ///
    /// Returns `false` when there was no text to flatten. Writing the string back replaces every
    /// representation on the pasteboard, which is what drops fonts, colors and links.
    @discardableResult
    public func flattenToPlainText() async -> Bool {
        guard let text = await pasteboard.readString(), text.isEmpty == false else {
            return false
        }
        await pasteboard.writeString(text)
        return true
    }

    /// Removes tracking parameters from a copied link.
    ///
    /// Returns the number of parameters removed, or `nil` when the clipboard did not hold a
    /// cleanable link. `nil` and `0` are deliberately distinct so a caller can say "that is not a
    /// link" rather than "already clean".
    public func cleanCopiedLink() async -> Int? {
        guard let text = await pasteboard.readString() else { return nil }
        let cleaner = makeCleaner()
        guard let cleaned = cleaner.clean(text) else { return nil }
        let removed = Self.removedParameterCount(from: text, to: cleaned)
        await pasteboard.writeString(cleaned)
        return removed
    }

    /// Empties the system clipboard.
    ///
    /// This does not delete Clipboard History entries. Clearing the clipboard and deleting saved
    /// items are separate actions, and only the second destroys what the user asked to keep.
    public func clearClipboard() async {
        await clearing.clear()
    }

    private static func removedParameterCount(from original: String, to cleaned: String) -> Int {
        let before = URLComponents(string: original)?.queryItems?.count ?? 0
        let after = URLComponents(string: cleaned)?.queryItems?.count ?? 0
        return max(0, before - after)
    }
}

/// Handler for ``ClipboardToolsIdentifiers/plainText``.
@MainActor
public struct FlattenClipboardCommandHandler: ModuleCommandHandling {
    private let operations: ClipboardToolsOperations

    /// Creates the handler.
    public init(operations: ClipboardToolsOperations) {
        self.operations = operations
    }

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(ClipboardToolsCommands.plainText.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to change the clipboard."
            )
        }
        let didChange = await operations.flattenToPlainText()
        guard didChange else {
            return .failed(message: "There’s no copied text to flatten.")
        }
        return .succeeded(
            message: "Clipboard is now plain text.",
            output: ModuleCommandOutput([ClipboardToolsOutputName.didChange: .boolean(true)])
        )
    }
}

/// Handler for ``ClipboardToolsIdentifiers/cleanURL``.
@MainActor
public struct CleanCopiedLinkCommandHandler: ModuleCommandHandling {
    private let operations: ClipboardToolsOperations

    /// Creates the handler.
    public init(operations: ClipboardToolsOperations) {
        self.operations = operations
    }

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(ClipboardToolsCommands.cleanURL.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to change the clipboard."
            )
        }
        guard let removed = await operations.cleanCopiedLink() else {
            return .failed(message: "The copied link has nothing to clean.")
        }
        return .succeeded(
            message: removed == 1 ? "Removed 1 tracking parameter." : "Removed \(removed) tracking parameters.",
            output: ModuleCommandOutput([
                ClipboardToolsOutputName.didChange: .boolean(true),
                ClipboardToolsOutputName.removedParameterCount: .integer(removed)
            ])
        )
    }
}

/// Handler for ``ClipboardToolsIdentifiers/clearNow``.
@MainActor
public struct ClearClipboardCommandHandler: ModuleCommandHandling {
    private let operations: ClipboardToolsOperations

    /// Creates the handler.
    public init(operations: ClipboardToolsOperations) {
        self.operations = operations
    }

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(ClipboardToolsCommands.clearNow.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to clear the clipboard."
            )
        }
        await operations.clearClipboard()
        return .succeeded(
            message: "Clipboard cleared.",
            output: ModuleCommandOutput([ClipboardToolsOutputName.didChange: .boolean(true)])
        )
    }
}

/// Handler for the module's presentation command.
@MainActor
public struct ClipboardToolsPresentationHandler: ModuleCommandHandling {
    /// Creates the handler.
    public init() {}

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        _ = invocation
        return .interactionRequired(message: "Opening Clipboard Tools needs Commandly’s window.")
    }
}
