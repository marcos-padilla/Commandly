import Foundation
import Observation
import AppKit
import AppCore
import Infrastructure
import SecurityKit

/// Sidebar destinations for the settings window.
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Startup, hotkey, appearance, and everyday Commandly preferences."
        case .permissions:
            return "Review access Commandly uses for calendar, files, and automation."
        case .about:
            return "Version details and project information."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

@Observable
@MainActor
final class SettingsViewModel {
    private let settingsStore: any AppSettingsStoring
    private let loginItemManager: any LoginItemManaging
    private let permissionService: any PermissionServicing
    private let privacySettingsOpener: any PrivacySettingsOpening
    let metadata: ApplicationMetadata

    var selectedPane: SettingsPane = .general
    var opensAtLogin: Bool
    var prefersCommandlyEmojiPicker: Bool
    var showMenuBarIcon: Bool
    var appearance: AppAppearancePreference
    var textSize: AppTextSizePreference
    var viewMode: AppViewModePreference
    var hasConfirmedOptionSpaceHotkey: Bool
    private(set) var permissionStates: [PermissionKind: PermissionState] = [:]
    private(set) var isUpdatingLoginItem = false
    private(set) var statusMessage: String?
    var onMenuBarIconChange: ((Bool) -> Void)?
    var onTextSizeChange: ((AppTextSizePreference) -> Void)?
    var onViewModeChange: ((AppViewModePreference) -> Void)?

    init(
        settingsStore: any AppSettingsStoring,
        loginItemManager: any LoginItemManaging,
        permissionService: any PermissionServicing,
        privacySettingsOpener: any PrivacySettingsOpening,
        metadata: ApplicationMetadata,
        onMenuBarIconChange: ((Bool) -> Void)? = nil,
        onTextSizeChange: ((AppTextSizePreference) -> Void)? = nil,
        onViewModeChange: ((AppViewModePreference) -> Void)? = nil
    ) {
        self.settingsStore = settingsStore
        self.loginItemManager = loginItemManager
        self.permissionService = permissionService
        self.privacySettingsOpener = privacySettingsOpener
        self.metadata = metadata
        self.onMenuBarIconChange = onMenuBarIconChange
        self.onTextSizeChange = onTextSizeChange
        self.onViewModeChange = onViewModeChange

        let settings = settingsStore.load()
        self.opensAtLogin = settings.opensAtLogin
        self.prefersCommandlyEmojiPicker = settings.prefersCommandlyEmojiPicker
        self.showMenuBarIcon = settings.showMenuBarIcon
        self.appearance = settings.appearance
        self.textSize = settings.textSize
        self.viewMode = settings.viewMode
        self.hasConfirmedOptionSpaceHotkey = settings.hasConfirmedOptionSpaceHotkey
        Self.applyAppearance(settings.appearance)
    }

    var hotkeyDisplay: String { "⌥ Space" }

    func onAppear() {
        Task {
            await refreshPermissions()
            await refreshLoginItem()
        }
    }

    func setOpensAtLogin(_ enabled: Bool) {
        opensAtLogin = enabled
        persist()
        statusMessage = nil
        isUpdatingLoginItem = true
        Task {
            defer { isUpdatingLoginItem = false }
            do {
                try await loginItemManager.setEnabled(enabled)
                await refreshLoginItem()
            } catch {
                opensAtLogin = false
                persist()
                statusMessage = "Couldn't update Open at Login."
            }
        }
    }

    func setPrefersCommandlyEmojiPicker(_ enabled: Bool) {
        prefersCommandlyEmojiPicker = enabled
        persist()
    }

    func setShowMenuBarIcon(_ enabled: Bool) {
        showMenuBarIcon = enabled
        persist()
        onMenuBarIconChange?(enabled)
        if enabled == false {
            statusMessage = "Menu bar icon hidden. Relaunch Commandly from Finder to show it again."
        } else {
            statusMessage = nil
        }
    }

    func setAppearance(_ value: AppAppearancePreference) {
        appearance = value
        Self.applyAppearance(value)
        persist()
    }

    func setTextSize(_ value: AppTextSizePreference) {
        textSize = value
        persist()
        onTextSizeChange?(value)
    }

    func setViewMode(_ value: AppViewModePreference) {
        viewMode = value
        persist()
        onViewModeChange?(value)
    }

    func refreshPermissions() async {
        var states: [PermissionKind: PermissionState] = [:]
        for kind in [PermissionKind.calendar, .contacts, .files, .accessibility] {
            states[kind] = await permissionService.state(for: kind)
        }
        permissionStates = states
    }

    func requestPermission(_ kind: PermissionKind) {
        Task {
            let state = await permissionService.state(for: kind)
            if state == .denied || state == .restricted {
                await privacySettingsOpener.open(pane(for: kind))
            } else {
                _ = await permissionService.request(kind)
            }
            await refreshPermissions()
        }
    }

    func state(for kind: PermissionKind) -> PermissionState {
        permissionStates[kind] ?? .notDetermined
    }

    private func refreshLoginItem() async {
        let status = await loginItemManager.status()
        if status == .enabled {
            opensAtLogin = true
            persist()
        }
        if status == .requiresApproval {
            statusMessage = "Approve Commandly in System Settings → Login Items."
        }
    }

    private func persist() {
        settingsStore.save(
            AppSettings(
                opensAtLogin: opensAtLogin,
                prefersCommandlyEmojiPicker: prefersCommandlyEmojiPicker,
                hasConfirmedOptionSpaceHotkey: hasConfirmedOptionSpaceHotkey,
                showMenuBarIcon: showMenuBarIcon,
                appearance: appearance,
                textSize: textSize,
                viewMode: viewMode
            )
        )
    }

    private func pane(for kind: PermissionKind) -> PrivacySettingsPane {
        switch kind {
        case .calendar: return .calendars
        case .contacts: return .contacts
        case .files: return .filesAndFolders
        case .accessibility: return .accessibility
        default: return .accessibility
        }
    }

    private static func applyAppearance(_ preference: AppAppearancePreference) {
        switch preference {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
