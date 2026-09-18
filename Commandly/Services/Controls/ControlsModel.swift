import AppKit
import CommandKit
import Foundation
import Observability
import Observation
import SecurityKit

/// The Controls tab: one switchboard over the behaviors Commandly can turn on and off.
///
/// Every working row reads and writes the same storage the rest of the app uses — the launcher
/// application registry for registered applications, the Command Wheel's own store for the radial
/// menu — so a switch here and the same setting in Settings can never disagree. Rows Commandly
/// has no implementation for stay visible and say so, rather than offering a switch that does
/// nothing.
@Observable
@MainActor
final class ControlsModel {
    private(set) var groups: [ControlGroupPresentation] = []
    /// Groups the user collapsed, by raw value.
    private(set) var collapsedGroups: Set<String> = []
    private(set) var errorMessage: String?

    private let registry: LauncherApplicationRegistry
    private let commandWheel: CommandWheelProfileStore
    private let keyboardTriggers: KeyboardTriggerSettingsModel
    private let permissions: any PermissionChecking
    private let store: any ControlsSettingsStoring
    private let logger: AppLogger
    /// Called when a switch changed a registered application's preferences, so the runtime can
    /// re-read the registry. Installed after the runtime finishes building itself.
    var onApplicationPreferencesChange: (() -> Void)?

    private var hasAccessibility = false
    private var observers = 0

    init(
        registry: LauncherApplicationRegistry,
        commandWheel: CommandWheelProfileStore,
        keyboardTriggers: KeyboardTriggerSettingsModel,
        permissions: any PermissionChecking,
        store: any ControlsSettingsStoring = UserDefaultsControlsSettingsStore(),
        logger: AppLogger = Loggers.application
    ) {
        self.registry = registry
        self.commandWheel = commandWheel
        self.keyboardTriggers = keyboardTriggers
        self.permissions = permissions
        self.store = store
        self.logger = logger
        self.collapsedGroups = store.collapsedGroups()
        rebuild()
    }

    func addObserver() {
        observers += 1
        refresh()
    }

    func removeObserver() {
        observers = max(0, observers - 1)
    }

    func refresh() {
        Task { [permissions] in
            hasAccessibility = await permissions.state(for: .accessibility) == .authorized
            rebuild()
        }
    }

    // MARK: - Collapsing

    func isCollapsed(_ group: ControlGroup) -> Bool {
        collapsedGroups.contains(group.rawValue)
    }

    func toggleCollapsed(_ group: ControlGroup) {
        if collapsedGroups.contains(group.rawValue) {
            collapsedGroups.remove(group.rawValue)
        } else {
            collapsedGroups.insert(group.rawValue)
        }
        store.saveCollapsedGroups(collapsedGroups)
    }

    // MARK: - Rows

    private func rebuild() {
        groups = ControlGroup.allCases.map { group in
            ControlGroupPresentation(
                group: group,
                rows: ControlRules.rows(
                    in: group,
                    isOn: { [weak self] in self?.isOn($0) ?? false },
                    unavailable: { [weak self] in self?.unavailable($0) ?? .notBuilt }
                )
            )
        }
    }

    func caption(for presentation: ControlPresentation) -> String {
        ControlRules.caption(for: presentation.control, unavailable: presentation.unavailable)
    }

    private func isOn(_ control: ControlID) -> Bool {
        switch control {
        case .appSwitcher:
            return registry.isEffectivelyEnabled(WindowSwitcherApplication.applicationID)
        case .appSwitcherLargeIcons:
            return switcherFlag(WindowSwitcherConfigurationVariable.replaceCommandTab)
        case .dockPreview:
            return switcherFlag(WindowSwitcherConfigurationVariable.dockPreviewsEnabled)
        case .radialMenu:
            return commandWheel.configurationSnapshot().isEnabled
        case .textSnippets:
            return keyboardTriggers.isEnabled
        case .highlightMode:
            return registry.isEffectivelyEnabled(HighlightModeApplication.applicationID)
        case .shelf:
            return registry.isEffectivelyEnabled(ShelfApplication.applicationID)
        default:
            return false
        }
    }

    private func unavailable(_ control: ControlID) -> ControlUnavailableReason? {
        switch control {
        case .appSwitcher, .appSwitcherLargeIcons, .dockPreview:
            // The switcher and its Dock previews read other applications' windows.
            guard registry.definition(for: WindowSwitcherApplication.applicationID) != nil else {
                return .notBuilt
            }
            return hasAccessibility ? nil : .needsAccessibility
        case .radialMenu, .shelf:
            return nil
        case .highlightMode:
            return hasAccessibility ? nil : .needsAccessibility
        case .textSnippets:
            return keyboardTriggers.canEnable ? nil : .notBuilt
        case .quitOnClose:
            // Commandly's auto-quit is a list of applications, not one global switch.
            return .configuredPerApplication
        case .maximizeWindows, .dockClickMinimize, .dockClickHide, .dockClickCycle,
             .invertScrolling, .focusFollowsMouse, .disableMouseAcceleration,
             .sideButtonNavigation, .keyboardDebounce, .threeFingerMiddleClick,
             .mouseButtonShortcuts, .superKey, .finderCutAndPaste:
            return .notBuilt
        }
    }

    // MARK: - Acting

    func setOn(_ isOn: Bool, for control: ControlID) {
        errorMessage = nil
        switch control {
        case .appSwitcher:
            setApplicationEnabled(isOn, for: WindowSwitcherApplication.applicationID)
        case .highlightMode:
            setApplicationEnabled(isOn, for: HighlightModeApplication.applicationID)
        case .shelf:
            setApplicationEnabled(isOn, for: ShelfApplication.applicationID)
        case .appSwitcherLargeIcons:
            setSwitcherFlag(isOn, variable: WindowSwitcherConfigurationVariable.replaceCommandTab)
        case .dockPreview:
            setSwitcherFlag(isOn, variable: WindowSwitcherConfigurationVariable.dockPreviewsEnabled)
        case .radialMenu:
            setRadialMenuEnabled(isOn)
        case .textSnippets:
            setTextSnippetsEnabled(isOn)
        default:
            return
        }
        rebuild()
    }

    private func setApplicationEnabled(_ isOn: Bool, for id: CommandID) {
        var preferences = registry.preferences(for: id)
        preferences.isEnabled = isOn
        registry.savePreferences(preferences, for: id)
        // Enabling or disabling an application changes what the launcher and its shortcuts
        // resolve, so the runtime re-reads the registry rather than drifting from it.
        onApplicationPreferencesChange?()
    }

    private func switcherFlag(_ variable: String) -> Bool {
        registry.preferences(for: WindowSwitcherApplication.applicationID)
            .configuration[variable]?.booleanValue ?? false
    }

    private func setSwitcherFlag(_ isOn: Bool, variable: String) {
        let id = WindowSwitcherApplication.applicationID
        var preferences = registry.preferences(for: id)
        preferences.configuration[variable] = .boolean(isOn)
        registry.savePreferences(preferences, for: id)
        onApplicationPreferencesChange?()
    }

    private func setRadialMenuEnabled(_ isOn: Bool) {
        Task { [commandWheel] in
            do {
                try await commandWheel.update { configuration in
                    configuration.isEnabled = isOn
                }
            } catch {
                errorMessage = "The radial menu setting could not be saved."
                logger.info("Radial menu could not be switched from the panel")
            }
            rebuild()
        }
    }

    private func setTextSnippetsEnabled(_ isOn: Bool) {
        Task { [keyboardTriggers] in
            if isOn {
                await keyboardTriggers.enable()
            } else {
                await keyboardTriggers.disable()
            }
            rebuild()
        }
    }
}

/// Persists the Controls tab's collapsed groups.
nonisolated protocol ControlsSettingsStoring: AnyObject, Sendable {
    func collapsedGroups() -> Set<String>
    func saveCollapsedGroups(_ collapsed: Set<String>)
}

/// UserDefaults-backed store for the collapsed groups.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set, and this reads and
/// writes one string array.
nonisolated final class UserDefaultsControlsSettingsStore: ControlsSettingsStoring, @unchecked Sendable {
    private static let key = "controls.collapsedGroups"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func collapsedGroups() -> Set<String> {
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        return Set(stored.filter { ControlGroup(rawValue: $0) != nil })
    }

    func saveCollapsedGroups(_ collapsed: Set<String>) {
        if collapsed.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(collapsed.sorted(), forKey: Self.key)
        }
    }
}

/// In-memory store for previews and tests.
///
/// `@unchecked Sendable`: one stored value guarded by `lock`.
nonisolated final class InMemoryControlsSettingsStore: ControlsSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var collapsed: Set<String> = []

    init(collapsed: Set<String> = []) {
        self.collapsed = collapsed
    }

    func collapsedGroups() -> Set<String> { lock.withLock { collapsed } }
    func saveCollapsedGroups(_ collapsed: Set<String>) { lock.withLock { self.collapsed = collapsed } }
}
