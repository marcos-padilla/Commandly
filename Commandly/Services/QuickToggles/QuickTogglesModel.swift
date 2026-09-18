import AppKit
import ApplicationServices
import Foundation
import Infrastructure
import Observability
import Observation
import SecurityKit

/// The Quick Toggles tab: everyday macOS switches, each one reporting the real system state
/// rather than a remembered intent.
///
/// Rows whose change App Sandbox does not allow stay visible and say so, with a route into the
/// System Settings page that can make the change, so the tab never shows a switch that does
/// nothing.
@Observable
@MainActor
final class QuickTogglesModel {
    private(set) var presentations: [QuickTogglePresentation] = []
    /// The last failure, shown inline under the rows until the next action.
    private(set) var errorMessage: String?
    /// Set while a destructive row is waiting for the user to confirm.
    var confirming: QuickToggleID?

    /// Rows the user took off the list, by raw value.
    private(set) var hiddenToggles: Set<String> = []

    private let microphone: any MicrophoneControlling
    private let appearance: any SystemAppearanceControlling
    private let trash: any FinderTrashEmptying
    private let screen: any ScreenControlling
    private let settings: any SystemSettingsOpening
    private let permissions: any PermissionChecking
    private let disks: DiskMetricsMonitor
    private let store: any QuickTogglesSettingsStoring
    private let logger: AppLogger

    private var isDarkMode: Bool?
    private var microphoneState: MicrophoneControlState?
    private var keyboardBacklightLevel: Double?
    private var hasAccessibility = false
    private var busyToggles: Set<QuickToggleID> = []
    private var refreshTask: Task<Void, Never>?
    private var appearanceObserver: NSObjectProtocol?
    private var observers = 0

    /// Broadcast by macOS whenever the system light/dark setting changes.
    private static let appearanceChangedNotification = Notification.Name(
        "AppleInterfaceThemeChangedNotification"
    )

    init(
        microphone: any MicrophoneControlling,
        disks: DiskMetricsMonitor,
        settings: any SystemSettingsOpening,
        permissions: any PermissionChecking,
        appearance: any SystemAppearanceControlling = SystemEventsAppearanceService(),
        trash: any FinderTrashEmptying = FinderAppleEventTrashService(),
        screen: any ScreenControlling = NativeScreenControlService(),
        store: any QuickTogglesSettingsStoring = UserDefaultsQuickTogglesSettingsStore(),
        logger: AppLogger = Loggers.application
    ) {
        self.microphone = microphone
        self.disks = disks
        self.settings = settings
        self.permissions = permissions
        self.appearance = appearance
        self.trash = trash
        self.screen = screen
        self.store = store
        self.logger = logger
        self.hiddenToggles = store.hiddenToggles()
        rebuild()
    }

    // MARK: - Lifecycle

    func addObserver() {
        observers += 1
        // The eject row counts real volumes, which the disk monitor already watches.
        disks.addObserver()
        if appearanceObserver == nil {
            appearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: Self.appearanceChangedNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { self.refresh() }
            }
        }
        refresh()
    }

    func removeObserver() {
        observers = max(0, observers - 1)
        disks.removeObserver()
        guard observers == 0 else { return }
        stopWatchingAppearance()
    }

    func tearDown() {
        observers = 0
        refreshTask?.cancel()
        refreshTask = nil
        stopWatchingAppearance()
    }

    private func stopWatchingAppearance() {
        guard let appearanceObserver else { return }
        DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        self.appearanceObserver = nil
    }

    // MARK: - State

    /// Re-reads everything the rows show. Cheap enough to run on every appearance change.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [microphone, appearance, screen, permissions] in
            let isDark = appearance.isDarkModeEnabled()
            let backlight = screen.keyboardBacklightLevel()
            let accessibility = await permissions.state(for: .accessibility) == .authorized
            let microphoneState = try? await microphone.state()
            guard Task.isCancelled == false else { return }

            self.isDarkMode = isDark
            self.keyboardBacklightLevel = backlight
            self.hasAccessibility = accessibility
            self.microphoneState = microphoneState
            self.rebuild()
            self.refreshTask = nil
        }
    }

    private func rebuild() {
        presentations = QuickToggleRules.visibleToggles(hidden: hiddenToggles)
            .map(presentation(for:))
    }

    private func presentation(for toggle: QuickToggleID) -> QuickTogglePresentation {
        QuickTogglePresentation(
            toggle: toggle,
            title: title(for: toggle),
            caption: caption(for: toggle),
            control: control(for: toggle),
            isBusy: busyToggles.contains(toggle)
        )
    }

    /// The row's live title, which the hidden-rows menu also uses.
    func title(for toggle: QuickToggleID) -> String {
        if let staticTitle = toggle.staticTitle { return staticTitle }
        switch toggle {
        case .appearance:
            return QuickToggleRules.appearanceTitle(isDark: isDarkMode ?? false)
        case .microphone:
            return QuickToggleRules.microphoneTitle(isMuted: microphoneState?.isMuted)
        case .hiddenFiles:
            return "Show hidden files"
        case .desktopIcons:
            return "Hide desktop icons"
        default:
            return toggle.rawValue
        }
    }

    private func caption(for toggle: QuickToggleID) -> String {
        switch toggle {
        case .appearance:
            return QuickToggleRules.appearanceCaption(isDark: isDarkMode)
        case .keyboardLight:
            guard keyboardBacklightLevel != nil else {
                return QuickToggleRules.unavailableCaption(.keyboardLight)
            }
            return QuickToggleRules.accessibilityCaption(
                granted: hasAccessibility,
                whenGranted: "Turns the keyboard backlight on or off."
            )
        case .microphone:
            return QuickToggleRules.microphoneCaption(
                deviceName: microphoneState?.deviceName,
                canChange: microphoneState?.canChangeMute ?? false
            )
        case .emptyTrash:
            return QuickToggleRules.trashCaption(isEmptying: busyToggles.contains(.emptyTrash))
        case .ejectDisks:
            return QuickToggleRules.ejectCaption(ejectableCount: disks.ejectableVolumes.count)
        case .hiddenFiles, .desktopIcons, .displaySleep:
            return QuickToggleRules.unavailableCaption(toggle)
        case .lockScreen:
            return QuickToggleRules.accessibilityCaption(
                granted: hasAccessibility,
                whenGranted: "Asks for the password to come back."
            )
        case .screenSaver:
            return "Starts right away, on every display."
        }
    }

    private func control(for toggle: QuickToggleID) -> QuickToggleControl {
        switch toggle {
        case .appearance:
            return isDarkMode == nil ? .unavailable : .action
        case .keyboardLight:
            guard let level = keyboardBacklightLevel, hasAccessibility else { return .unavailable }
            return .toggle(isOn: level > 0.01)
        case .microphone:
            guard microphoneState?.canChangeMute == true else { return .unavailable }
            return .action
        case .emptyTrash:
            return .action
        case .ejectDisks:
            return disks.ejectableVolumes.isEmpty ? .unavailable : .action
        case .hiddenFiles, .desktopIcons, .displaySleep:
            return .unavailable
        case .lockScreen:
            return hasAccessibility ? .action : .unavailable
        case .screenSaver:
            return .action
        }
    }

    // MARK: - Actions

    /// Runs one row. A row that needs confirmation only arms it; `confirm` does the work.
    func activate(_ toggle: QuickToggleID) {
        errorMessage = nil
        guard busyToggles.contains(toggle) == false else { return }
        guard toggle.needsConfirmation == false else {
            confirming = toggle
            return
        }
        perform(toggle)
    }

    func confirm(_ toggle: QuickToggleID) {
        confirming = nil
        perform(toggle)
    }

    func cancelConfirmation() {
        confirming = nil
    }

    /// Opens the System Settings page that can make a change Commandly cannot.
    func openSettings(for toggle: QuickToggleID) {
        guard let pane = toggle.settingsPane else { return }
        Task { [settings] in
            do {
                _ = try await settings.open(pane)
            } catch {
                errorMessage = (error as? SystemSettingsNavigationError)?.message
                    ?? "System Settings could not be opened."
            }
        }
    }

    /// Takes a row off the list. Its place is remembered, so showing it again restores the order.
    func hide(_ toggle: QuickToggleID) {
        hiddenToggles.insert(toggle.rawValue)
        store.saveHiddenToggles(hiddenToggles)
        rebuild()
    }

    /// Puts one hidden row back in its place in the list.
    func show(_ toggle: QuickToggleID) {
        hiddenToggles.remove(toggle.rawValue)
        store.saveHiddenToggles(hiddenToggles)
        rebuild()
    }

    func showAllToggles() {
        hiddenToggles.removeAll()
        store.saveHiddenToggles(hiddenToggles)
        rebuild()
    }

    var hiddenToggleList: [QuickToggleID] {
        QuickToggleID.allCases.filter { hiddenToggles.contains($0.rawValue) }
    }

    private func perform(_ toggle: QuickToggleID) {
        busyToggles.insert(toggle)
        rebuild()

        Task {
            do {
                try await run(toggle)
            } catch {
                errorMessage = Self.message(for: error, toggle: toggle)
                logger.info("Quick toggle \(toggle.rawValue) did not complete")
            }
            busyToggles.remove(toggle)
            refresh()
        }
    }

    private func run(_ toggle: QuickToggleID) async throws {
        switch toggle {
        case .appearance:
            try await appearance.setDarkModeEnabled(isDarkMode != true)
        case .keyboardLight:
            try screen.setKeyboardBacklight(on: (keyboardBacklightLevel ?? 0) <= 0.01)
        case .microphone:
            let isMuted = microphoneState?.isMuted ?? false
            microphoneState = try await microphone.setMuted(isMuted == false)
        case .emptyTrash:
            try await trash.emptyTrash()
        case .ejectDisks:
            disks.ejectAll()
            if let message = disks.ejectError { errorMessage = message }
        case .lockScreen:
            try screen.lockScreen()
        case .screenSaver:
            try screen.startScreenSaver()
        case .hiddenFiles, .desktopIcons, .displaySleep:
            // These rows are never activatable; the guard exists so a future change cannot make
            // one act without an implementation behind it.
            throw ScreenControlError.actionFailed
        }
    }

    private static func message(for error: Error, toggle: QuickToggleID) -> String {
        switch error {
        case SystemAppearanceError.notAuthorized:
            return "Allow Commandly to control System Events in Privacy & Security → Automation, then try again."
        case SystemAppearanceError.systemEventsUnavailable:
            return "System Events is not available, so the appearance could not be changed."
        case FinderTrashError.notAuthorized:
            return "Allow Commandly to control the Finder in Privacy & Security → Automation, then try again."
        case FinderTrashError.finderUnavailable:
            return "The Finder is not running, so the Trash could not be emptied."
        case ScreenControlError.needsAccessibility:
            return "Grant Accessibility permission so Commandly can send that key."
        case ScreenControlError.screenSaverUnavailable:
            return "The screen saver could not be found on this Mac."
        case let error as MicrophoneControlError:
            if case .muteControlUnavailable(let deviceName) = error {
                return "\(deviceName) exposes no system-wide mute control."
            }
            return "The microphone could not be changed."
        default:
            return "\(toggle.rawValue) could not be completed."
        }
    }
}

/// Persists which Quick Toggles rows the user hid.
nonisolated protocol QuickTogglesSettingsStoring: AnyObject, Sendable {
    func hiddenToggles() -> Set<String>
    func saveHiddenToggles(_ hidden: Set<String>)
}

/// UserDefaults-backed store for the hidden rows.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set, and this reads and
/// writes one string array.
nonisolated final class UserDefaultsQuickTogglesSettingsStore: QuickTogglesSettingsStoring, @unchecked Sendable {
    private static let key = "quickToggles.hidden"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hiddenToggles() -> Set<String> {
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        // Unknown values are dropped rather than hiding a row that no longer exists.
        return Set(stored.filter { QuickToggleID(rawValue: $0) != nil })
    }

    func saveHiddenToggles(_ hidden: Set<String>) {
        if hidden.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(hidden.sorted(), forKey: Self.key)
        }
    }
}

/// In-memory store for previews and tests.
///
/// `@unchecked Sendable`: one stored value guarded by `lock`.
nonisolated final class InMemoryQuickTogglesSettingsStore: QuickTogglesSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var hidden: Set<String> = []

    init(hidden: Set<String> = []) {
        self.hidden = hidden
    }

    func hiddenToggles() -> Set<String> { lock.withLock { hidden } }
    func saveHiddenToggles(_ hidden: Set<String>) { lock.withLock { self.hidden = hidden } }
}
