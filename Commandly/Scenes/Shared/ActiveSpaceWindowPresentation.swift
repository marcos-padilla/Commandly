import AppKit

/// Display geometry captured before Commandly becomes the active application.
///
/// The value remains stable while AppKit creates and configures the requested window, without
/// retaining an `NSScreen` across a display reconfiguration.
struct WindowPresentationTarget: Sendable, Equatable {
    let visibleFrame: CGRect
}

/// One explicit request to present a floating Commandly window.
struct WindowPresentationRequest: Sendable, Equatable {
    let generation: UInt64
    let screenTarget: WindowPresentationTarget?

    static let initial = WindowPresentationRequest(
        generation: 0,
        screenTarget: nil
    )

    func next(screenTarget: WindowPresentationTarget?) -> WindowPresentationRequest {
        WindowPresentationRequest(
            generation: generation &+ 1,
            screenTarget: screenTarget
        )
    }
}

/// Resolves the display the user is actively working on before Commandly takes focus.
@MainActor
enum WindowPresentationTargetResolver {
    static func activeTarget() -> WindowPresentationTarget? {
        if let screen = NSScreen.main {
            return WindowPresentationTarget(visibleFrame: screen.visibleFrame)
        }

        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
        return (mouseScreen ?? NSScreen.screens.first).map {
            WindowPresentationTarget(visibleFrame: $0.visibleFrame)
        }
    }
}

/// Reports the hosting window when SwiftUI attaches this otherwise invisible AppKit view.
///
/// A one-shot deferred `view.window` lookup can still be `nil` during the first scene
/// materialization. `viewDidMoveToWindow` is the lifecycle event that guarantees cold-open
/// presentation is not deferred until a second SwiftUI update.
@MainActor
final class WindowAttachmentProbeView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfPossible()
    }

    func attachIfPossible() {
        guard let window else { return }
        onWindowAttached?(window)
    }
}

/// Applies and presents a floating overlay in the currently active macOS Space.
@MainActor
enum ActiveSpaceWindowPresenter {
    /// A deterministic collection role for transient Commandly overlays.
    ///
    /// `canJoinAllSpaces` keeps the same live window visible as the user changes Spaces, while
    /// `canJoinAllApplications` lets it join another application's full-screen Space. The
    /// transient/cycle flags keep these utility surfaces out of Mission Control and normal window
    /// cycling.
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .transient,
        .ignoresCycle,
    ]

    static func applyOverlayBehavior(to window: NSWindow) {
        window.collectionBehavior = overlayCollectionBehavior
    }

    /// Orders the configured window into the active Space before Commandly takes focus.
    static func present(_ window: NSWindow) {
        window.orderFrontRegardless()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
