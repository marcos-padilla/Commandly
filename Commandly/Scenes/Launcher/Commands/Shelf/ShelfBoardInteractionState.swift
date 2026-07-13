import Observation

/// Transient presentation state shared between Shelf chrome and the board view.
@Observable
@MainActor
final class ShelfBoardInteractionState {
    var isFocused = true
    var isDragging = false
}
