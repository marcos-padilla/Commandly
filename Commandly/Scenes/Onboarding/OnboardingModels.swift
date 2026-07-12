import Foundation

/// Ordered steps in the first-run onboarding flow.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case features
    case preferences
    case permissions
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .features:
            return "Features"
        case .preferences:
            return "Preferences"
        case .permissions:
            return "Permissions"
        case .ready:
            return "Ready"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .welcome:
            return "Start Setup"
        case .features, .preferences, .permissions:
            return "Continue"
        case .ready:
            return "Open Commandly"
        }
    }

    var showsBackButton: Bool {
        self != .welcome
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

/// A feature highlighted during the features onboarding step.
struct OnboardingFeature: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let blurb: String

    static let showcase: [OnboardingFeature] = [
        OnboardingFeature(
            id: "launcher",
            title: "Quick Launcher",
            systemImage: "command",
            blurb: "Open apps and commands instantly from the keyboard."
        ),
        OnboardingFeature(
            id: "search",
            title: "Unified Search",
            systemImage: "magnifyingglass",
            blurb: "Find apps, files, and actions in one focused place."
        ),
        OnboardingFeature(
            id: "clipboard",
            title: "Clipboard History",
            systemImage: "doc.on.clipboard",
            blurb: "Opt-in history so recent copies stay within reach."
        ),
        OnboardingFeature(
            id: "links",
            title: "Quick Links",
            systemImage: "link",
            blurb: "Jump to the sites and tools you use every day."
        ),
        OnboardingFeature(
            id: "snippets",
            title: "Snippets",
            systemImage: "text.alignleft",
            blurb: "Expand short triggers into text you reuse often."
        ),
        OnboardingFeature(
            id: "windows",
            title: "Window Layouts",
            systemImage: "rectangle.split.2x2",
            blurb: "Arrange windows quickly when you enable accessibility."
        )
    ]
}
