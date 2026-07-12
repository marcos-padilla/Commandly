import Foundation
import Observation
import Infrastructure
import SecurityKit

@Observable
@MainActor
final class OnboardingViewModel {
    private(set) var step: OnboardingStep
    private let statusStore: any OnboardingStatusStoring
    private let settingsStore: any AppSettingsStoring
    private let loginItemManager: any LoginItemManaging
    private let permissionService: any PermissionServicing
    private let privacySettingsOpener: any PrivacySettingsOpening
    private let onFinished: () -> Void
    private var activationTask: Task<Void, Never>?

    let features: [OnboardingFeature]
    let permissionItems: [OnboardingPermissionItem]

    var opensAtLogin: Bool
    var prefersCommandlyEmojiPicker: Bool
    private(set) var hasConfirmedOptionSpaceHotkey: Bool
    private(set) var loginItemStatus: LoginItemStatus
    private(set) var loginItemErrorMessage: String?
    private(set) var isUpdatingLoginItem = false
    private(set) var permissionStatuses: [OnboardingPermissionItem: OnboardingPermissionStatus]
    private(set) var hotkeyPhase: HotkeyActivationPhase = .waiting
    private(set) var pressedKeyIDs: Set<MacKeyboardKeyID> = []

    init(
        statusStore: any OnboardingStatusStoring,
        settingsStore: any AppSettingsStoring,
        loginItemManager: any LoginItemManaging,
        permissionService: any PermissionServicing,
        privacySettingsOpener: any PrivacySettingsOpening,
        initialStep: OnboardingStep = .welcome,
        features: [OnboardingFeature] = OnboardingFeature.showcase,
        permissionItems: [OnboardingPermissionItem] = OnboardingPermissionItem.allCases,
        onFinished: @escaping () -> Void = {}
    ) {
        self.statusStore = statusStore
        self.settingsStore = settingsStore
        self.loginItemManager = loginItemManager
        self.permissionService = permissionService
        self.privacySettingsOpener = privacySettingsOpener
        self.step = initialStep
        self.features = features
        self.permissionItems = permissionItems
        self.onFinished = onFinished

        let settings = settingsStore.load()
        self.opensAtLogin = settings.opensAtLogin
        self.prefersCommandlyEmojiPicker = settings.prefersCommandlyEmojiPicker
        self.hasConfirmedOptionSpaceHotkey = settings.hasConfirmedOptionSpaceHotkey
        self.loginItemStatus = .disabled
        self.permissionStatuses = Dictionary(
            uniqueKeysWithValues: permissionItems.map { ($0, .idle) }
        )
    }

    var stepIndex: Int {
        step.rawValue
    }

    var stepCount: Int {
        OnboardingStep.allCases.count
    }

    var canGoBack: Bool {
        step.showsBackButton && hotkeyPhase == .waiting
    }

    var showsPrimaryAction: Bool {
        hotkeyPhase == .waiting
    }

    var primaryActionTitle: String {
        step.primaryActionTitle
    }

    var loginItemApprovalHint: String? {
        guard loginItemStatus == .requiresApproval else { return nil }
        return "Approve Commandly under System Settings → General → Login Items."
    }

    var isCelebratingHotkey: Bool {
        hotkeyPhase == .celebrating
    }

    var isOptionKeyHighlighted: Bool {
        pressedKeyIDs.contains(.leftOption)
            || pressedKeyIDs.contains(.rightOption)
            || isCelebratingHotkey
    }

    var isSpaceKeyHighlighted: Bool {
        pressedKeyIDs.contains(.space) || isCelebratingHotkey
    }

    func status(for item: OnboardingPermissionItem) -> OnboardingPermissionStatus {
        permissionStatuses[item] ?? .idle
    }

    func preparePreferencesStep() async {
        await refreshLoginItemStatus()
    }

    func preparePermissionsStep() async {
        await refreshPermissionStatuses()
    }

    func updatePressedKeys(_ keys: Set<MacKeyboardKeyID>) {
        guard hotkeyPhase == .waiting else { return }
        pressedKeyIDs = keys
    }

    func handleOptionSpaceHotkey() {
        beginActivation(confirmedHotkey: true)
    }

    func goBack() {
        guard canGoBack, let previous = step.previous else { return }
        step = previous
    }

    func advance() {
        if step == .ready {
            beginActivation(confirmedHotkey: false)
            return
        }

        if let next = step.next {
            step = next
            if next == .preferences {
                Task { await preparePreferencesStep() }
            } else if next == .permissions {
                Task { await preparePermissionsStep() }
            }
            return
        }
        finish()
    }

    func setOpensAtLogin(_ enabled: Bool) {
        opensAtLogin = enabled
        persistSettings()
        loginItemErrorMessage = nil
        isUpdatingLoginItem = true

        Task {
            defer { isUpdatingLoginItem = false }
            do {
                try await loginItemManager.setEnabled(enabled)
                await refreshLoginItemStatus()
                if enabled == false {
                    opensAtLogin = false
                } else if loginItemStatus == .enabled || loginItemStatus == .requiresApproval {
                    opensAtLogin = true
                }
                persistSettings()
            } catch {
                opensAtLogin = false
                persistSettings()
                loginItemErrorMessage = "Couldn't update Open at Login. Try again from Settings later."
                await refreshLoginItemStatus()
            }
        }
    }

    func setPrefersCommandlyEmojiPicker(_ enabled: Bool) {
        prefersCommandlyEmojiPicker = enabled
        persistSettings()
    }

    func handlePermissionAction(_ item: OnboardingPermissionItem) {
        let current = status(for: item)
        guard current.showsActionAsEnabled else { return }

        switch current.state {
        case .denied, .restricted:
            Task {
                await privacySettingsOpener.open(item.recoveryPane)
            }
        case .notDetermined:
            Task {
                await requestPermission(item)
            }
        case .authorized:
            break
        }
    }

    func finish() {
        activationTask?.cancel()
        activationTask = nil
        hotkeyPhase = .finished
        persistSettings()
        statusStore.markOnboardingCompleted()
        onFinished()
    }

    private func beginActivation(confirmedHotkey: Bool) {
        guard step == .ready, hotkeyPhase == .waiting else { return }

        if confirmedHotkey {
            hasConfirmedOptionSpaceHotkey = true
            pressedKeyIDs.formUnion([.leftOption, .space])
        }
        persistSettings()
        hotkeyPhase = .celebrating

        activationTask?.cancel()
        activationTask = Task { [weak self] in
            // Choreographed celebration delay before entering the app — not used as async sync.
            let delay = UInt64(MotionCelebrationNanoseconds.duration)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func requestPermission(_ item: OnboardingPermissionItem) async {
        var requesting = status(for: item)
        requesting.isRequesting = true
        permissionStatuses[item] = requesting

        var aggregate: PermissionState = .authorized
        for kind in item.permissionKinds {
            let result = await permissionService.request(kind)
            aggregate = Self.merge(aggregate, with: result)
        }

        permissionStatuses[item] = OnboardingPermissionStatus(state: aggregate, isRequesting: false)
    }

    private func refreshPermissionStatuses() async {
        for item in permissionItems {
            var aggregate: PermissionState = .authorized
            for kind in item.permissionKinds {
                let result = await permissionService.state(for: kind)
                aggregate = Self.merge(aggregate, with: result)
            }
            permissionStatuses[item] = OnboardingPermissionStatus(state: aggregate, isRequesting: false)
        }
    }

    /// Combines multiple underlying permissions into one row state (most restrictive wins).
    private static func merge(_ lhs: PermissionState, with rhs: PermissionState) -> PermissionState {
        let rank: [PermissionState: Int] = [
            .authorized: 0,
            .notDetermined: 1,
            .denied: 2,
            .restricted: 3
        ]
        let left = rank[lhs] ?? 0
        let right = rank[rhs] ?? 0
        return left >= right ? lhs : rhs
    }

    private func persistSettings() {
        settingsStore.save(
            AppSettings(
                opensAtLogin: opensAtLogin,
                prefersCommandlyEmojiPicker: prefersCommandlyEmojiPicker,
                hasConfirmedOptionSpaceHotkey: hasConfirmedOptionSpaceHotkey
            )
        )
    }

    private func refreshLoginItemStatus() async {
        loginItemStatus = await loginItemManager.status()
        if loginItemStatus == .enabled {
            opensAtLogin = true
            persistSettings()
        }
    }
}

extension OnboardingViewModel {
    /// Builds an in-memory view model for SwiftUI previews and local UI experiments.
    @MainActor
    static func preview(
        step: OnboardingStep = .ready,
        settings: AppSettings = .default
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(settings: settings),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: step
        )
    }
}

/// Nanosecond helper so the view model does not import DesignSystem solely for a Double.
private enum MotionCelebrationNanoseconds {
    static let duration: UInt64 = 1_250_000_000
}
