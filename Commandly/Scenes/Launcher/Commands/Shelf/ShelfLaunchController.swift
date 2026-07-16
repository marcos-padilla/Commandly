import CommandKit
import Foundation

/// How Shelf was requested from the menu bar or launcher.
enum ShelfEntryMode: String, Sendable, Equatable {
    case empty
    case fromClipboard
}

/// One explicit request to create or replace the singleton Shelf board.
struct ShelfPresentationRequest: Sendable, Equatable {
    let generation: UInt64
    let entryMode: ShelfEntryMode
    let screenTarget: WindowPresentationTarget?

    static let initial = ShelfPresentationRequest(
        generation: 0,
        entryMode: .empty,
        screenTarget: nil
    )

    func next(
        entryMode: ShelfEntryMode,
        screenTarget: WindowPresentationTarget?
    ) -> ShelfPresentationRequest {
        ShelfPresentationRequest(
            generation: generation &+ 1,
            entryMode: entryMode,
            screenTarget: screenTarget
        )
    }
}

/// Fixed system-wide Shelf shortcuts registered through Commandly's Carbon hot-key adapter.
enum ShelfGlobalShortcut: CaseIterable, Sendable {
    case newShelf
    case newShelfFromClipboard

    var commandID: CommandID {
        switch self {
        case .newShelf:
            return CommandID(rawValue: "shelf.shortcut.new")
        case .newShelfFromClipboard:
            return CommandID(rawValue: "shelf.shortcut.clipboard")
        }
    }

    var hotKey: LauncherHotKey {
        switch self {
        case .newShelf:
            return LauncherHotKey(keyCode: 49, modifiers: [.option, .shift])
        case .newShelfFromClipboard:
            return LauncherHotKey(keyCode: 0, modifiers: [.option, .shift])
        }
    }

    var entryMode: ShelfEntryMode {
        switch self {
        case .newShelf: return .empty
        case .newShelfFromClipboard: return .fromClipboard
        }
    }

    static func resolve(_ commandID: CommandID) -> ShelfGlobalShortcut? {
        allCases.first { $0.commandID == commandID }
    }
}

/// Preferred on-screen anchor for a newly opened Shelf board.
enum ShelfPreferredCorner: String, Sendable, Equatable, CaseIterable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft

    /// Initial placement when the user has not selected a preferred corner.
    static let defaultValue: ShelfPreferredCorner = .topRight

    var title: String {
        switch self {
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        }
    }

    static func resolve(_ rawValue: String?) -> ShelfPreferredCorner {
        guard let rawValue, let corner = Self(rawValue: rawValue) else {
            return defaultValue
        }
        return corner
    }
}

/// Coordinates menu-bar / launcher requests to present the floating Shelf board.
@MainActor
final class ShelfLaunchController {
    var onPresent: ((ShelfEntryMode) -> Void)?

    func present(_ mode: ShelfEntryMode) {
        onPresent?(mode)
    }
}
