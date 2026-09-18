import CommandKit
import Foundation
import Observation

enum CelebrationActionID {
    static let replay = CommandActionID(rawValue: "celebration.replay")
    static let close = CommandActionID(rawValue: "celebration.close")
}

@MainActor
@Observable
final class CelebrationViewModel: LauncherApplicationModel {
    private(set) var burst: CelebrationBurst?
    private(set) var reducesMotion = false
    private(set) var isActive = false
    private var hasStarted = false
    var showsActionsMenu = false
    var statusMessage: String? { nil }
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let onGoBack: () -> Void

    init(now: @escaping () -> Date = Date.init, onGoBack: @escaping () -> Void) {
        self.now = now
        self.onGoBack = onGoBack
    }

    var footerActions: [CommandActionDescriptor] {
        [CommandActionDescriptor(id: CelebrationActionID.replay, title: "Celebrate Again",
                                 isPrimary: true, keyHint: .return)]
    }
    var menuActions: [CommandActionDescriptor] { [] }

    func start(reducesMotion: Bool) {
        guard hasStarted == false else { return }
        hasStarted = true
        isActive = true
        self.reducesMotion = reducesMotion
        replay()
    }

    func replay() {
        guard isActive else { return }
        burst = reducesMotion ? nil : CelebrationBurst(startedAt: now())
    }

    func updateReducedMotion(_ value: Bool) {
        reducesMotion = value
        // Changing accessibility settings never starts a new animation by itself.
        if value { burst = nil }
    }

    func moveSelection(offset: Int) {}

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case CelebrationActionID.replay: replay()
        case CelebrationActionID.close: goBack()
        default: break
        }
    }

    func handleEscape() -> Bool {
        stop()
        return false
    }

    func goBack() {
        guard isActive else { return }
        stop()
        onGoBack()
    }

    func stop() {
        hasStarted = true
        isActive = false
        burst = nil
        showsActionsMenu = false
    }
}
