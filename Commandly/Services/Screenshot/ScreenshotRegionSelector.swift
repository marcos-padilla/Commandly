import AppKit
import CoreGraphics
import Foundation
import Infrastructure
import QuartzCore

nonisolated struct ScreenshotRegion: Sendable {
    let captureRect: CGRect
    let scale: CGFloat
    let layout: ScreenshotDisplayLayout
}

@MainActor
protocol ScreenshotRegionSelecting: AnyObject {
    func select() async throws -> ScreenshotRegion
    func cancel()
}

/// Selection overlays inspect geometry only. No screen image is obtained before completion.
@MainActor
final class ScreenshotRegionSelector: ScreenshotRegionSelecting {
    private var panels: [ScreenshotRegionPanel] = []
    private var continuation: CheckedContinuation<ScreenshotRegion, Error>?
    private var displays: [(frame: CGRect, scale: CGFloat)] = []
    private var primaryTop: CGFloat = 0
    private var selection: CGRect?
    private var screenObserver: NSObjectProtocol?
    private var selectionID: UUID?
    private var selectedLayout: ScreenshotDisplayLayout?

    func select() async throws -> ScreenshotRegion {
        try Task.checkCancellation()
        cancel()
        let screens = NSScreen.screens
        selectedLayout = try ScreenshotNativeDisplayLayout.current()
        guard let primary = screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { throw ScreenshotCaptureError.selectionUnavailable }
        let id = UUID()
        selectionID = id
        primaryTop = primary.frame.maxY
        displays = screens.map { ($0.frame, $0.backingScaleFactor) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                show(on: screens)
            }
        } onCancel: {
            Task { @MainActor [weak self] in if self?.selectionID == id { self?.cancel() } }
        }
    }

    func cancel() { finish(.failure(ScreenshotCaptureError.cancelled)) }

    private func show(on screens: [NSScreen]) {
        let id = selectionID
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.selectionID == id { self?.cancel() } }
        }
        let mouse = NSEvent.mouseLocation
        for screen in screens {
            let panel = ScreenshotRegionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.isExcludedFromWindowsMenu = true
            let view = ScreenshotRegionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.onChange = { [weak self] rect in self?.setSelection(rect) }
            view.onFinish = { [weak self] in self?.complete() }
            view.onCancel = { [weak self] in self?.cancel() }
            view.onKeyboard = { [weak self] code, resize in self?.adjustSelection(keyCode: code, resize: resize, within: screen.frame) }
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(mouse) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }

    private func setSelection(_ rect: CGRect) {
        selection = rect
        for panel in panels {
            guard let view = panel.contentView as? ScreenshotRegionView else { continue }
            view.selection = rect
            view.needsDisplay = true
            view.setAccessibilityValue("Selected region, \(Int(rect.width)) by \(Int(rect.height)) points")
        }
    }

    private func adjustSelection(keyCode: UInt16, resize: Bool, within frame: CGRect) {
        var rect = selection ?? CGRect(x: frame.midX - 160, y: frame.midY - 100, width: 320, height: 200)
        let dx: CGFloat = keyCode == 123 ? -10 : keyCode == 124 ? 10 : 0
        let dy: CGFloat = keyCode == 125 ? -10 : keyCode == 126 ? 10 : 0
        if resize {
            rect.size.width = max(2, rect.width + dx)
            rect.size.height = max(2, rect.height + dy)
        } else { rect.origin.x += dx; rect.origin.y += dy }
        setSelection(rect)
    }

    private func complete() {
        do {
            guard let selection, let selectedLayout,
                  selectedLayout == (try ScreenshotNativeDisplayLayout.current()) else {
                throw ScreenshotCaptureError.selectionInvalid
            }
            let rect = try ScreenshotGeometry.captureRect(appKitRect: selection, primaryDisplayTop: primaryTop)
            let scale = try ScreenshotGeometry.scale(for: selection, displays: displays)
            _ = try ScreenshotGeometry.outputSize(points: rect.size, scale: scale)
            finish(.success(ScreenshotRegion(captureRect: rect, scale: scale, layout: selectedLayout)))
        } catch { finish(.failure(error)) }
    }

    private func finish(_ result: Result<ScreenshotRegion, Error>) {
        let pending = continuation
        continuation = nil
        selectionID = nil
        selectedLayout = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        displays.removeAll()
        selection = nil
        // Commit overlay removal before the caller submits its one-shot screenshot request.
        CATransaction.flush()
        pending?.resume(with: result)
    }
}

@MainActor
private final class ScreenshotRegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenshotRegionView: NSView {
    var screenFrame: CGRect = .zero
    var selection: CGRect?
    var onChange: ((CGRect) -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onKeyboard: ((UInt16, Bool) -> Void)?
    private var start: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Select a screenshot region. Drag to select. Arrow keys position a region; Shift and arrows resize. Return captures. Escape cancels.")
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.23).setFill()
        bounds.fill()
        if let selection {
            let local = selection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            NSColor.clear.setFill()
            local.fill(using: .copy)
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(rect: local)
            outline.lineWidth = 2
            outline.stroke()
        }
        let text = "Drag a region · Arrow keys move · Shift + arrows resize · Return captures · Esc cancels"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: max(12, (bounds.width - size.width) / 2 - 14), y: bounds.height - 72,
                         width: min(bounds.width - 24, size.width + 28), height: 42)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(in: box.insetBy(dx: 14, dy: 12), withAttributes: attributes)
    }
    override func mouseDown(with event: NSEvent) { start = screenPoint(for: event) }
    override func mouseDragged(with event: NSEvent) {
        guard let start, let end = screenPoint(for: event) else { return }
        onChange?(ScreenshotGeometry.rectangle(from: start, to: end))
    }
    override func mouseUp(with event: NSEvent) {
        guard let start, let end = screenPoint(for: event) else { return }
        onChange?(ScreenshotGeometry.rectangle(from: start, to: end))
        self.start = nil
        onFinish?()
    }
    private func screenPoint(for event: NSEvent) -> CGPoint? {
        guard let window else { return nil }
        return ScreenshotRegionEventPosition.screenPoint(for: event, convert: window.convertPoint(toScreen:))
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: onFinish?()
        case 123...126: onKeyboard?(event.keyCode, event.modifierFlags.contains(.shift))
        default: super.keyDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}


/// Resolves the delivered event rather than sampling a pointer that may already have moved.
@MainActor
enum ScreenshotRegionEventPosition {
    static func screenPoint(for event: NSEvent, convert: (CGPoint) -> CGPoint) -> CGPoint {
        convert(event.locationInWindow)
    }
}

@MainActor
enum ScreenshotNativeDisplayLayout {
    static func current() throws -> ScreenshotDisplayLayout {
        let displays = try NSScreen.screens.map { screen -> ScreenshotDisplayGeometry in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
                throw ScreenshotCaptureError.selectionUnavailable
            }
            return ScreenshotDisplayGeometry(id: id, frame: screen.frame, scale: screen.backingScaleFactor)
        }
        let primary = CGMainDisplayID()
        guard displays.contains(where: { $0.id == primary }) else { throw ScreenshotCaptureError.selectionUnavailable }
        return ScreenshotDisplayLayout(primaryDisplayID: primary, displays: displays)
    }
}
