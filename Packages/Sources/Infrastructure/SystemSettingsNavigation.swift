/// Fixed macOS settings destinations. These identify pages, never system-setting mutations.
public enum SystemSettingsPane: String, CaseIterable, Sendable, Hashable {
    case displays, appearance, wifi, bluetooth, network, sound, keyboard, trackpad, mouse
    case accessibility, privacySecurity, notifications, focus, battery, general
    case softwareUpdate, storage, loginItems, dateTime, languageRegion, printers, timeMachine
}

/// A successful NSWorkspace handoff is a navigation request, not proof of which UI is visible.
public enum SystemSettingsNavigationResult: Sendable, Equatable {
    /// The verified pane URL was dispatched to the built-in System Settings application.
    case requestedPane(SystemSettingsPane)
    /// The application was opened. A non-nil pane means the requested destination was unavailable
    /// or its URL dispatch failed; the user must choose that page in System Settings.
    case openedApplication(fallbackFor: SystemSettingsPane?)
}

/// Local settings navigation, only after an explicit action. Implementations must not mutate
/// settings, request permissions, send Apple events, or execute shell commands.
public protocol SystemSettingsOpening: Sendable {
    /// Opens one fixed destination, or the System Settings application when nil.
    func open(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationResult
}

/// Recoverable navigation failures. No file paths or private settings values appear in errors.
public enum SystemSettingsNavigationError: Error, Sendable, Equatable {
    case unavailable, navigationFailed, invalidRequest, disabled

    /// A concise explanation suitable for a launcher status or recovery view.
    public var message: String {
        switch self {
        case .unavailable: "System Settings is unavailable. Open it from the Apple menu."
        case .navigationFailed: "System Settings couldn’t be opened. Try again or open it from the Apple menu."
        case .invalidRequest: "That settings destination is unavailable. Choose an item from the settings catalog."
        case .disabled: "This settings command is disabled in Commandly."
        }
    }
}
