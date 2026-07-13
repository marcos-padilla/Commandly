import Foundation

/// How Shelf was requested from the menu bar or launcher.
enum ShelfEntryMode: String, Sendable, Equatable {
    case empty
    case fromClipboard
}

/// Preferred on-screen anchor for a newly opened Shelf board.
enum ShelfPreferredCorner: String, Sendable, Equatable, CaseIterable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft

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
            return .bottomRight
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
