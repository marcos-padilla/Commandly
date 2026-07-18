import CoreGraphics

nonisolated enum CommandWheelInputMode: Sendable, Equatable {
    case holdAndRelease
    case toggle
}

/// Owns all active-session input resources. Pointer sampling exists in both modes; local/global
/// click monitors exist only in toggle mode and are removed synchronously on stop.
@MainActor
final class CommandWheelInputLifecycle {
    private let pointerSampler: CommandWheelPointerSampler
    private let eventMonitors: any CommandWheelEventMonitorManaging

    private var panelFrame: (() -> CGRect?)?
    private var interactiveRegionContains: ((CGPoint) -> Bool)?
    private var onPointerSample: ((CommandWheelPointerSample) -> Void)?
    private var onInsideClick: ((CGPoint) -> Void)?
    private var onOutsideClick: (() -> Void)?

    private(set) var mode: CommandWheelInputMode?

    var isActive: Bool { mode != nil }
    var isSampling: Bool { pointerSampler.isSampling }
    var hasClickMonitors: Bool { eventMonitors.hasMonitors }
    var currentPointerLocation: CGPoint { pointerSampler.currentPointerLocation }

    init(
        pointerSampler: CommandWheelPointerSampler = CommandWheelPointerSampler(),
        eventMonitors: any CommandWheelEventMonitorManaging =
            NSEventCommandWheelEventMonitorManager()
    ) {
        self.pointerSampler = pointerSampler
        self.eventMonitors = eventMonitors
    }

    func start(
        mode: CommandWheelInputMode,
        panelFrame: @escaping () -> CGRect?,
        interactiveRegionContains: @escaping (CGPoint) -> Bool,
        onPointerSample: @escaping (CommandWheelPointerSample) -> Void,
        onInsideClick: @escaping (CGPoint) -> Void,
        onOutsideClick: @escaping () -> Void
    ) {
        stop()
        self.mode = mode
        self.panelFrame = panelFrame
        self.interactiveRegionContains = interactiveRegionContains
        self.onPointerSample = onPointerSample
        self.onInsideClick = onInsideClick
        self.onOutsideClick = onOutsideClick

        pointerSampler.start { [weak self] sample in
            self?.onPointerSample?(sample)
        }

        guard mode == .toggle else { return }
        eventMonitors.install(
            localHandler: { [weak self] event in
                self?.handleLocalClick(event) ?? .passThrough
            },
            globalHandler: { [weak self] _ in
                self?.onOutsideClick?()
            }
        )
    }

    /// Samples the latest global pointer synchronously before releasing all input resources.
    func sampleFinalAndStop() {
        pointerSampler.sampleFinalAndStop()
        removeNonPointerResources()
    }

    func stop() {
        pointerSampler.stop()
        removeNonPointerResources()
    }

    private func handleLocalClick(
        _ event: CommandWheelClickEvent
    ) -> CommandWheelLocalClickDisposition {
        guard let frame = panelFrame?() else {
            onOutsideClick?()
            return .passThrough
        }
        guard frame.contains(event.screenLocation),
              interactiveRegionContains?(event.screenLocation) == true else {
            onOutsideClick?()
            return .passThrough
        }
        guard event.button == .left else { return .passThrough }
        onInsideClick?(event.screenLocation)
        return .consume
    }

    private func removeNonPointerResources() {
        eventMonitors.removeAll()
        mode = nil
        panelFrame = nil
        interactiveRegionContains = nil
        onPointerSample = nil
        onInsideClick = nil
        onOutsideClick = nil
    }

    isolated deinit {
        pointerSampler.stop()
        eventMonitors.removeAll()
    }
}
