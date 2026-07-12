import Foundation

/// Persists whether the user has finished first-run onboarding.
protocol OnboardingStatusStoring: AnyObject, Sendable {
    var hasCompletedOnboarding: Bool { get }
    func markOnboardingCompleted()
    func resetOnboardingCompletion()
}

/// UserDefaults-backed onboarding completion flag.
///
/// Onboarding completion is a non-secret preference; UserDefaults is appropriate
/// until a durable Persistence backend is selected.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set of this flag;
/// the type only exposes synchronous preference reads/writes with no other shared mutable state.
final class UserDefaultsOnboardingStatusStore: OnboardingStatusStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "onboarding.hasCompleted") {
        self.defaults = defaults
        self.key = key
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: key)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: key)
    }

    func resetOnboardingCompletion() {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory store for tests and previews.
///
/// `@unchecked Sendable`: mutated only from `@MainActor` app/test code in this foundation phase.
final class InMemoryOnboardingStatusStore: OnboardingStatusStoring, @unchecked Sendable {
    private(set) var hasCompletedOnboarding: Bool

    init(hasCompletedOnboarding: Bool = false) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    func resetOnboardingCompletion() {
        hasCompletedOnboarding = false
    }
}
