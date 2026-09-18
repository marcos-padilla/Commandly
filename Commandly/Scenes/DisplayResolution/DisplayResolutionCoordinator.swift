import AppCore
import Foundation
import Infrastructure
import Observation

nonisolated enum DisplayResolutionPhase: Equatable { case idle, loading, applying, preview, keeping, reverting, recovery }

/// Retained by AppRuntime, independent of launcher sessions. Mutation tasks are never abandoned on close.
@Observable
@MainActor
final class DisplayResolutionCoordinator {
    private(set) var phase: DisplayResolutionPhase = .idle
    private(set) var catalog: DisplayResolutionCatalog?
    private(set) var selectedDisplayID: UUID?
    private(set) var selectedModeID: UUID?
    private(set) var preview: DisplayResolutionPreview?
    private(set) var remainingSeconds = 0
    private(set) var statusMessage: String?
    private(set) var attemptedSessionKeep = false
    @ObservationIgnored private let controller: any DisplayResolutionControlling
    @ObservationIgnored private let clock: any AppCore.Clock
    @ObservationIgnored private let ticker: any DisplayResolutionTickScheduling
    @ObservationIgnored private let environment: any DisplayResolutionEnvironmentObserving
    @ObservationIgnored private let window: any DisplayResolutionWindowPresenting
    @ObservationIgnored private let openSettings: @MainActor () async throws -> Void
    @ObservationIgnored private let onRequestQuit: @MainActor () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var revertRequested = false
    @ObservationIgnored private var closeAfterOperation = false
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var terminationCompletion: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var allowsQuitWithoutExactRestore = false

    init(controller: any DisplayResolutionControlling, clock: any AppCore.Clock,
         ticker: any DisplayResolutionTickScheduling, environment: any DisplayResolutionEnvironmentObserving,
         window: any DisplayResolutionWindowPresenting, openSettings: @escaping @MainActor () async throws -> Void,
         onRequestQuit: @escaping @MainActor () -> Void) {
        self.controller = controller; self.clock = clock; self.ticker = ticker; self.environment = environment
        self.window = window; self.openSettings = openSettings; self.onRequestQuit = onRequestQuit
    }

    var selectedDisplay: ResolutionDisplay? { catalog?.displays.first { $0.id == selectedDisplayID } }
    var selectedMode: DisplayResolutionMode? { selectedDisplay?.modes.first { $0.id == selectedModeID } }
    var canApply: Bool {
        phase == .idle && activeID == nil && selectedDisplay?.unavailableReason == nil
            && selectedMode?.canPreview == true && selectedModeID != selectedDisplay?.currentModeID
    }
    var hasPendingChange: Bool { activeID != nil }
    /// The shared termination gate rechecks this immediately before replying to AppKit.
    /// An explicit recovery quit can waive exact restoration for only that quit attempt.
    var requiresTerminationReview: Bool { activeID != nil && allowsQuitWithoutExactRestore == false }
    var canKeep: Bool { phase == .preview && deadline.map { clock.monotonicTime() < $0 } == true }

    func show() {
        isVisible = true; closeAfterOperation = false
        window.present(self)
        environment.start { [weak self] in self?.environmentChanged() }
        if activeID == nil, phase != .loading { refresh() }
        else { tick(); window.ensureVisible() }
    }

    func refresh(preservingStatus: Bool = false) {
        guard activeID == nil else { return }
        let previousLoad = loadTask
        previousLoad?.cancel(); generation = UUID(); let token = generation
        phase = .loading
        if preservingStatus == false { statusMessage = nil }
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await previousLoad?.value
            guard Task.isCancelled == false, generation == token else { return }
            do {
                let value = try await controller.catalog()
                guard Task.isCancelled == false, generation == token, activeID == nil else { return }
                catalog = value
                selectedDisplayID = value.displays.first?.id
                selectedModeID = value.displays.first?.currentModeID
                phase = .idle
            } catch {
                guard Task.isCancelled == false, generation == token else { return }
                phase = .idle; catalog = nil; selectedDisplayID = nil; selectedModeID = nil
                statusMessage = Self.message(error)
            }
        }
    }

    func selectDisplay(_ id: UUID) {
        guard phase == .idle, catalog?.displays.contains(where: { $0.id == id }) == true else { return }
        selectedDisplayID = id; selectedModeID = selectedDisplay?.currentModeID
    }
    func selectMode(_ id: UUID) {
        guard phase == .idle, selectedDisplay?.modes.contains(where: { $0.id == id }) == true else { return }
        selectedModeID = id
    }
    func moveModeSelection(offset: Int) {
        guard phase == .idle, let modes = selectedDisplay?.modes, modes.isEmpty == false else { return }
        let current = modes.firstIndex { $0.id == selectedModeID } ?? 0
        selectedModeID = modes[min(modes.count - 1, max(0, current + offset.signum()))].id
    }

    func apply() {
        guard canApply, let catalog, let selectedDisplayID, let selectedModeID else { return }
        let id = UUID(); let deadline = clock.monotonicTime().advanced(by: .seconds(15))
        activeID = id; self.deadline = deadline; attemptedSessionKeep = false; revertRequested = false
        allowsQuitWithoutExactRestore = false; phase = .applying; remainingSeconds = 15
        statusMessage = "Applying a temporary preview…"
        ticker.start { [weak self] in self?.tick() }
        let selection = DisplayResolutionSelection(catalogID: catalog.id, displayID: selectedDisplayID, modeID: selectedModeID)
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { actionTask = nil }
            do {
                preview = try await controller.preview(selection, id: id, deadline: deadline)
                guard activeID == id else { return }
                let now = clock.monotonicTime()
                if revertRequested || now >= deadline {
                    await performRevert(id: id, explanation: "The preview was canceled or its deadline passed.")
                } else {
                    phase = .preview
                    statusMessage = "Keep this mode for this login session, or revert."
                    updateCountdown(now: now)
                    window.ensureVisible()
                }
            } catch { await performRevert(id: id, explanation: Self.message(error)) }
        }
    }

    func keep() {
        guard canKeep, let id = activeID else { tick(); return }
        phase = .keeping; attemptedSessionKeep = true; ticker.cancel()
        statusMessage = "Keeping the selected mode for this login session…"
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { actionTask = nil }
            do {
                try await controller.keepPreview(id: id)
                finishChange(message: "Mode kept for this login session. Permanent display settings were not changed.")
            } catch { await performRevert(id: id, explanation: Self.message(error)) }
        }
    }

    func revert() {
        guard let id = activeID else { return }
        if phase == .applying { revertRequested = true; statusMessage = "Canceling the preview and restoring the original mode…"; return }
        guard phase == .preview || phase == .recovery else { return }
        phase = .reverting
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { actionTask = nil }
            await performRevert(id: id, explanation: nil)
        }
    }

    func requestClose() {
        if activeID == nil { closeNow(); return }
        closeAfterOperation = true
        revert()
    }

    /// Run after recording preparation and before note review. Failure leaves recovery visible.
    /// Preparation does not stop observation: another feature may still cancel the quit.
    func requestCloseForTermination(completion: @escaping @MainActor (Bool) -> Void) {
        guard terminationCompletion == nil else { completion(false); return }
        guard requiresTerminationReview else { completion(true); return }
        terminationCompletion = completion
        revert()
    }

    /// Withdraw only quit approval. A requested display restoration must still finish safely.
    func cancelPendingTermination() {
        allowsQuitWithoutExactRestore = false
        if let completion = terminationCompletion {
            terminationCompletion = nil
            completion(false)
        }
    }

    func quitWithoutExactRestore() {
        guard phase == .recovery else { return }
        allowsQuitWithoutExactRestore = true
        onRequestQuit()
    }

    func openSystemSettings() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await openSettings() }
            catch { statusMessage = "System Settings could not open. Open it from the Apple menu, then choose Displays." }
        }
    }

    func tick() {
        guard let deadline, activeID != nil else { return }
        let now = clock.monotonicTime()
        updateCountdown(now: now)
        if now >= deadline {
            if phase == .applying { revertRequested = true }
            else if phase == .preview { revert() }
        }
    }

    private func updateCountdown(now: ContinuousClock.Instant) {
        guard let deadline else { return }
        let duration = now.duration(to: deadline).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        remainingSeconds = max(0, Int(ceil(seconds)))
    }

    func environmentChanged() {
        window.ensureVisible()
        tick()
        guard let id = activeID, phase == .preview else {
            if activeID == nil, isVisible { refresh(preservingStatus: true) }
            return
        }
        validationTask?.cancel()
        validationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await controller.validatePreview(id: id) }
            catch {
                guard Task.isCancelled == false, activeID == id, phase == .preview else { return }
                statusMessage = "The display configuration changed. Ending this preview safely."
                revert()
            }
        }
    }

    func waitForWorkForTesting() async { await validationTask?.value; await actionTask?.value; await loadTask?.value }

    private func performRevert(id: UUID, explanation: String?) async {
        phase = .reverting; ticker.cancel(); statusMessage = "Restoring the original mode…"
        do {
            let outcome = try await controller.revertPreview(id: id)
            let result: String
            switch outcome {
            case .restored, .alreadyOriginal: result = "Original mode restored."
            case .noPendingChange: result = "No display change was applied."
            case .superseded: result = "The mode changed outside this preview. That newer choice was preserved; the original was not restored."
            }
            finishChange(message: [explanation, result].compactMap { $0 }.joined(separator: " "))
        } catch {
            phase = .recovery
            statusMessage = "The original mode could not be restored. \(Self.message(error)) Retry Revert, or open System Settings and choose Displays."
            window.ensureVisible()
            if let completion = terminationCompletion { terminationCompletion = nil; completion(false) }
        }
    }

    private func finishChange(message: String) {
        ticker.cancel(); validationTask?.cancel(); validationTask = nil
        activeID = nil; deadline = nil; preview = nil; remainingSeconds = 0; revertRequested = false
        phase = .idle; statusMessage = message
        if let completion = terminationCompletion { terminationCompletion = nil; completion(true) }
        if closeAfterOperation { closeAfterOperation = false; closeNow() }
        else if isVisible { refresh(preservingStatus: true) }
    }

    private func closeNow() {
        isVisible = false; generation = UUID(); loadTask?.cancel(); validationTask?.cancel()
        environment.stop(); window.close()
    }

    private static func message(_ error: any Error) -> String {
        switch error as? DisplayResolutionError {
        case .staleSelection, .configurationChanged: "The displays or their modes changed. Refresh before choosing again."
        case .unsupportedDisplay: "Inactive or mirrored displays must be configured in Displays Settings."
        case .unsafeMode: "This mode is too small to keep the confirmation controls readable."
        case .disconnected: "The original display is disconnected. Reconnect it before retrying."
        case .modeUnavailable: "The exact original mode is unavailable. No substitute mode was selected."
        case .expired: "The fifteen-second preview deadline passed."
        case .modeSubstituted: "macOS selected a different mode than the one requested."
        case .busy: "Another display operation is still finishing."
        case .keepFailed: "macOS could not confirm the requested login-session setting."
        case .revertFailed: "macOS did not confirm restoration of the exact original mode."
        default: "macOS could not complete the display operation. Another full-screen app or display change may prevent it."
        }
    }
}
