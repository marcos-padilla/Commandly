import Infrastructure
import Observation

/// Transient presentation state shared between Shelf chrome and the board view.
@Observable
@MainActor
final class ShelfBoardInteractionState {
    var isFocused = true
    var isDraggingShelfItems = false
    var isBoardDropTargeted = false
    var targetedAction: NativeShareDestination?
    var showsInstantActions = false
    var incomingItemCount = 0

    /// Window movement yields to Shelf's explicit item drag source as soon as that session begins.
    var allowsWindowDragging: Bool {
        isDraggingShelfItems == false
    }

    var incomingItemDescription: String {
        switch incomingItemCount {
        case 1: return "1 item"
        case 2...: return "\(incomingItemCount) items"
        default: return "files and folders"
        }
    }

    func beginDropSession(itemCount: Int) {
        guard isDraggingShelfItems == false else { return }
        if itemCount > 0 {
            incomingItemCount = itemCount
        }
        showsInstantActions = true
    }

    func updateBoardDropTarget(isTargeted: Bool) {
        guard isDraggingShelfItems == false else {
            isBoardDropTargeted = false
            return
        }
        isBoardDropTargeted = isTargeted
        if isTargeted {
            showsInstantActions = true
        }
    }

    func updateActionDropTarget(
        _ action: NativeShareDestination,
        isTargeted: Bool
    ) {
        guard isDraggingShelfItems == false else {
            targetedAction = nil
            return
        }
        if isTargeted {
            targetedAction = action
            showsInstantActions = true
        } else if targetedAction == action {
            targetedAction = nil
        }
    }

    func beginShelfItemDrag() {
        isDraggingShelfItems = true
        endDropSession()
    }

    func endShelfItemDrag() {
        isDraggingShelfItems = false
        endDropSession()
    }

    func endDropSession() {
        isBoardDropTargeted = false
        targetedAction = nil
        showsInstantActions = false
        incomingItemCount = 0
    }
}
