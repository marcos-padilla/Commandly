import AppKit
import SwiftUI

/// Native hit region that moves Shelf without making its file-content background draggable.
struct ShelfWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ShelfWindowDragRegionView {
        ShelfWindowDragRegionView(frame: .zero)
    }

    func updateNSView(_ nsView: ShelfWindowDragRegionView, context: Context) {}
}

/// Hands the original mouse-down event to the Window Server for native window movement.
final class ShelfWindowDragRegionView: NSView {
    /// Keep AppKit from interpreting this view as draggable window background. The view owns the
    /// mouse-down event and explicitly hands it to `performDrag(with:)` below.
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
