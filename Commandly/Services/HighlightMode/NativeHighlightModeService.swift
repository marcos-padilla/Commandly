import AppKit
import Infrastructure
import Observation
import SecurityKit
import SwiftUI

@MainActor
@Observable
final class HighlightOverlayModel {
    struct ClickPulse: Identifiable {
        let id = UUID()
        let location: CGPoint
        let createdAt: Date
        let duration: TimeInterval
    }

    struct KeyIndicator {
        let text: String
        let expiresAt: Date
    }

    var configuration: HighlightModeConfiguration
    var cursorLocation = NSEvent.mouseLocation
    var clickPulses: [ClickPulse] = []
    var keyIndicator: KeyIndicator?

    init(configuration: HighlightModeConfiguration) {
        self.configuration = configuration
    }

    /// Whether click feedback currently needs display-linked animation frames.
    var requiresContinuousRendering: Bool {
        clickPulses.isEmpty == false
    }

    @discardableResult
    func recordClick(at location: CGPoint, now: Date = Date()) -> ClickPulse {
        let duration = configuration.displayDuration.seconds
        clickPulses = Array(
            clickPulses
                .filter { now.timeIntervalSince($0.createdAt) < $0.duration }
                .suffix(7)
        )
        let pulse = ClickPulse(location: location, createdAt: now, duration: duration)
        clickPulses.append(pulse)
        return pulse
    }

    func removeClick(id: UUID) {
        clickPulses.removeAll { $0.id == id }
    }

    func showKeyText(_ text: String, now: Date = Date()) {
        keyIndicator = KeyIndicator(
            text: text,
            expiresAt: now.addingTimeInterval(configuration.displayDuration.seconds)
        )
    }
}

/// Native, click-through overlay and event-monitor adapter for Highlight Mode.
///
/// Keyboard characters remain only in `HighlightOverlayModel` long enough to render the transient
/// overlay. They are never persisted, copied, uploaded, or sent to Commandly's logger.
@MainActor
final class NativeHighlightModeService: HighlightModeControlling {
    private let permissionService: any PermissionServicing
    private let model: HighlightOverlayModel
    private var eventMonitors: [Any] = []
    private var overlayPanels: [HighlightOverlayPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var typedText = ""
    private var inputClearTimer: Timer?
    private var clickClearTimers: [UUID: Timer] = [:]

    private(set) var state = HighlightModeState(isEnabled: false)

    init(
        permissionService: any PermissionServicing,
        initialConfiguration: HighlightModeConfiguration = .default
    ) {
        self.permissionService = permissionService
        self.model = HighlightOverlayModel(configuration: initialConfiguration)
    }

    func setEnabled(
        _ isEnabled: Bool,
        configuration: HighlightModeConfiguration
    ) async throws -> HighlightModeState {
        updateConfiguration(configuration)

        guard isEnabled else {
            stop()
            return state
        }
        guard state.isEnabled == false else { return state }

        var permission = await permissionService.state(for: .accessibility)
        if permission != .authorized {
            permission = await permissionService.request(.accessibility)
        }
        guard permission == .authorized else {
            throw HighlightModeError.accessibilityDenied
        }

        do {
            try installEventMonitors()
            installScreenObserver()
            rebuildOverlayPanels()
            state = HighlightModeState(isEnabled: true)
            return state
        } catch {
            stop()
            throw error
        }
    }

    func updateConfiguration(_ configuration: HighlightModeConfiguration) {
        model.configuration = configuration
        if configuration.showsTypedText == false {
            typedText = ""
        }
    }

    func stop() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        overlayPanels.forEach { $0.orderOut(nil) }
        overlayPanels.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        typedText = ""
        inputClearTimer?.invalidate()
        inputClearTimer = nil
        clickClearTimers.values.forEach { $0.invalidate() }
        clickClearTimers.removeAll()
        model.clickPulses.removeAll()
        model.keyIndicator = nil
        state = HighlightModeState(isEnabled: false)
    }

    private func installEventMonitors() throws {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .keyDown,
        ]

        guard let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.consume(event)
            }
        ) else {
            throw HighlightModeError.eventMonitoringUnavailable
        }
        guard let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.consume(event)
                return event
            }
        ) else {
            NSEvent.removeMonitor(globalMonitor)
            throw HighlightModeError.eventMonitoringUnavailable
        }
        eventMonitors = [globalMonitor, localMonitor]
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenParametersDidChange()
            }
        }
    }

    private func screenParametersDidChange() {
        guard state.isEnabled else { return }
        rebuildOverlayPanels()
    }

    private func rebuildOverlayPanels() {
        overlayPanels.forEach { $0.orderOut(nil) }
        overlayPanels = NSScreen.screens.map { screen in
            let panel = HighlightOverlayPanel(screen: screen, model: model)
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func consume(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let pointerLocation = NSEvent.mouseLocation
            model.cursorLocation = pointerLocation
            guard model.configuration.showsMouseClicks else { return }
            let pulse = model.recordClick(at: pointerLocation)
            scheduleClickRemoval(pulse)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard model.configuration.showsCursorSpotlight else { return }
            model.cursorLocation = NSEvent.mouseLocation

        case .keyDown:
            // Keyboard feedback follows the display containing the pointer, even when the cursor
            // spotlight itself is disabled.
            model.cursorLocation = NSEvent.mouseLocation
            consumeKeyDown(event)

        default:
            break
        }
    }

    private func consumeKeyDown(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShortcut = modifiers.contains(.command)
            || modifiers.contains(.control)
            || modifiers.contains(.option)

        if isShortcut, model.configuration.showsKeyboardShortcuts {
            typedText = ""
            showKeyText(Self.shortcutTitle(for: event, modifiers: modifiers))
            return
        }
        guard model.configuration.showsTypedText else { return }

        switch event.keyCode {
        case 36, 76:
            typedText.append(" ↩")
        case 48:
            typedText.append(" ⇥")
        case 51:
            if typedText.isEmpty == false { typedText.removeLast() }
        case 53:
            typedText = ""
        default:
            let visibleCharacters = (event.characters ?? "").filter { character in
                character.isNewline == false && character.isASCIIControl == false
            }
            typedText.append(contentsOf: visibleCharacters)
        }

        typedText = String(typedText.suffix(42))
        if typedText.isEmpty {
            model.keyIndicator = nil
        } else {
            showKeyText(typedText)
        }
    }

    private func showKeyText(_ text: String) {
        model.showKeyText(text)
        inputClearTimer?.invalidate()
        inputClearTimer = Timer.scheduledTimer(
            withTimeInterval: model.configuration.displayDuration.seconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.typedText = ""
                self?.model.keyIndicator = nil
                self?.inputClearTimer = nil
            }
        }
    }

    private func scheduleClickRemoval(_ pulse: HighlightOverlayModel.ClickPulse) {
        clickClearTimers[pulse.id]?.invalidate()
        clickClearTimers[pulse.id] = Timer.scheduledTimer(
            withTimeInterval: pulse.duration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model.removeClick(id: pulse.id)
                self?.clickClearTimers[pulse.id] = nil
            }
        }
    }

    private static func shortcutTitle(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> String {
        var title = ""
        if modifiers.contains(.control) { title += "⌃" }
        if modifiers.contains(.option) { title += "⌥" }
        if modifiers.contains(.shift) { title += "⇧" }
        if modifiers.contains(.command) { title += "⌘" }
        return title + keyTitle(for: event)
    }

    private static func keyTitle(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "↩",
            48: "⇥",
            49: "Space",
            51: "⌫",
            53: "Esc",
            117: "⌦",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
        ]
        if let specialKey = specialKeys[event.keyCode] { return specialKey }
        let characters = event.charactersIgnoringModifiers ?? ""
        let visible = characters.filter { $0.isASCIIControl == false && $0.isNewline == false }
        return visible.isEmpty ? "Key \(event.keyCode)" : visible.uppercased()
    }
}

private final class HighlightOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    init(screen: NSScreen, model: HighlightOverlayModel) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        contentView = NSHostingView(
            rootView: HighlightModeOverlayView(
                model: model,
                screenFrame: screen.frame
            )
        )
    }
}

private struct HighlightModeOverlayView: View {
    @Bindable var model: HighlightOverlayModel
    let screenFrame: CGRect

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawSpotlight(in: &context, size: size)
            }

            // A display-linked timeline is needed only while click rings are expanding. Cursor
            // movement invalidates the static spotlight directly, and key expiration uses its
            // one-shot timer, so an idle overlay performs no continuous rendering.
            if model.requiresContinuousRendering {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, _ in
                        drawClicks(in: &context, date: timeline.date)
                    }
                }
            }

            if let indicator = model.keyIndicator,
               indicator.expiresAt > .now,
               screenFrame.contains(model.cursorLocation) {
                VStack {
                    Spacer()
                    Text(indicator.text)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(accentColor.opacity(0.8), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
                        .padding(.bottom, 56)
                }
                .padding(.horizontal, 40)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawSpotlight(in context: inout GraphicsContext, size: CGSize) {
        guard model.configuration.showsCursorSpotlight else { return }
        var dimmingPath = Path(CGRect(origin: .zero, size: size))
        if screenFrame.contains(model.cursorLocation) {
            let point = localPoint(model.cursorLocation)
            let diameter = model.configuration.spotlightSize.diameter
            dimmingPath.addEllipse(
                in: CGRect(
                    x: point.x - diameter / 2,
                    y: point.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
        }
        context.fill(
            dimmingPath,
            with: .color(.black.opacity(0.42)),
            style: FillStyle(eoFill: true)
        )
    }

    private func drawClicks(in context: inout GraphicsContext, date: Date) {
        guard model.configuration.showsMouseClicks else { return }
        for pulse in model.clickPulses where screenFrame.contains(pulse.location) {
            let elapsed = date.timeIntervalSince(pulse.createdAt)
            guard elapsed >= 0, elapsed < pulse.duration else { continue }
            let progress = elapsed / pulse.duration
            let radius = 18 + (32 * progress)
            let opacity = 1 - progress
            let point = localPoint(pulse.location)
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(accentColor.opacity(opacity)),
                lineWidth: 5 - (2 * progress)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - 7,
                    y: point.y - 7,
                    width: 14,
                    height: 14
                )),
                with: .color(accentColor.opacity(opacity * 0.72))
            )
        }
    }

    private func localPoint(_ globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: globalPoint.x - screenFrame.minX,
            y: screenFrame.maxY - globalPoint.y
        )
    }

    private var accentColor: Color {
        switch model.configuration.accent {
        case .blue: .cyan
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        }
    }
}

private extension HighlightModeSpotlightSize {
    var diameter: CGFloat {
        switch self {
        case .compact: 130
        case .medium: 190
        case .large: 270
        }
    }
}

private extension HighlightModeDisplayDuration {
    var seconds: TimeInterval {
        switch self {
        case .short: 0.8
        case .standard: 1.5
        case .long: 2.5
        }
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.allSatisfy { $0.value < 32 || $0.value == 127 }
    }
}
