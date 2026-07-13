import Observation

/// State for the floating Shelf board. File staging is intentionally not implemented yet.
@Observable
@MainActor
final class ShelfBoardModel {
    let entryMode: ShelfEntryMode
    private let onClose: () -> Void

    init(entryMode: ShelfEntryMode, onClose: @escaping () -> Void) {
        self.entryMode = entryMode
        self.onClose = onClose
    }

    var accessibilityLabel: String {
        switch entryMode {
        case .empty:
            return "Shelf"
        case .fromClipboard:
            return "Shelf from Clipboard"
        }
    }

    func close() {
        onClose()
    }
}
