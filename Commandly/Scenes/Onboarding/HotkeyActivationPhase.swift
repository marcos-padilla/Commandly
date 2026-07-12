import Foundation

/// Visual / completion phases for the final hotkey onboarding step.
enum HotkeyActivationPhase: Equatable, Sendable {
    case waiting
    case celebrating
    case finished
}
