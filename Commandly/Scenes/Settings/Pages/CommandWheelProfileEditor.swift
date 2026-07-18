import AppKit
import DesignSystem
import SecurityKit
import SwiftUI

struct CommandWheelProfileEditor: View {
    @Bindable var model: CommandWheelSettingsModel
    let onChooseCommand: (Int) -> Void
    let onAddPage: (Int) -> Void
    let permissionState: PermissionState
    let onOpenPermissions: () -> Void

    var body: some View {
        Group {
            if model.store.phase == .failed {
                storageRecovery
            } else if model.store.phase == .loading {
                ProgressView("Loading Command Wheel profiles…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile = model.selectedProfile {
                SettingsPageLayout(maxWidth: 920) {
                    VStack(alignment: .leading, spacing: 24) {
                        SettingsPageHeader(
                            title: "Command Wheel",
                            subtitle: "Build radial command profiles for pointer, click, and keyboard use."
                        )
                        feedback
                        CommandWheelProfileBasics(
                            model: model,
                            profile: profile,
                            permissionState: permissionState,
                            onOpenPermissions: onOpenPermissions
                        )
                        CommandWheelPagesAndSlotsSection(
                            model: model,
                            profile: profile,
                            onChooseCommand: onChooseCommand,
                            onAddPage: onAddPage,
                            onOpenPermissions: onOpenPermissions
                        )
                        CommandWheelBehaviorSection(model: model, profile: profile)
                        CommandWheelContextRulesSection(model: model, profile: profile)
                        resetSection(profile)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No wheel profile selected",
                    systemImage: "circle.hexagongrid",
                    description: Text("Create or select a profile to begin editing.")
                )
            }
        }
    }

    private var storageRecovery: some View {
        SettingsPageLayout(maxWidth: 720) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "Command Wheel Storage Needs Attention",
                    subtitle: "Commandly preserved the existing file because it could not be safely loaded."
                )
                SettingsStatusBanner(
                    message: model.store.errorMessage
                        ?? "Command Wheel settings could not be loaded.",
                    tint: .red,
                    systemImage: "exclamationmark.triangle.fill"
                )
                SettingsSection(
                    "Recovery",
                    footer: "This is never automatic. Restoring replaces the unreadable or unsupported file with current built-in defaults."
                ) {
                    HStack {
                        Text("Keep the original file unless you explicitly restore defaults.")
                            .commandlyFont(size: 10.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore Command Wheel Defaults", role: .destructive) {
                            Task {
                                await model.perform {
                                    try await model.restoreDefaultsAfterStorageFailure()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("command-wheel.storage.restore")
                    }
                    .padding(.horizontal, Spacing.xs.rawValue)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = model.errorMessage {
            SettingsStatusBanner(
                message: error,
                tint: .red,
                systemImage: "exclamationmark.triangle.fill"
            )
        } else if let status = model.statusMessage {
            SettingsStatusBanner(
                message: status,
                tint: .green,
                systemImage: "checkmark.circle.fill"
            )
        }
    }

    private func resetSection(_ profile: CommandWheelProfile) -> some View {
        SettingsSection(
            "Restore Defaults",
            footer: "Restore replaces the complete layout, appearance, interaction, shortcut, and context configuration. The profile name and default selection are retained."
        ) {
            HStack {
                Text("Remove custom pages, rules, labels, shortcut, and behavior changes.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore \(profile.name)", role: .destructive) {
                    Task {
                        await model.perform {
                            try await model.resetProfile(profile.id)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("command-wheel.profile.reset")
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.vertical, 8)
        }
    }
}

private struct CommandWheelProfileBasics: View {
    @Bindable var model: CommandWheelSettingsModel
    let profile: CommandWheelProfile
    let permissionState: PermissionState
    let onOpenPermissions: () -> Void

    var body: some View {
        SettingsSection("Profile") {
            VStack(spacing: 10) {
                CommandWheelNameEditor(
                    title: "Name",
                    value: profile.name,
                    accessibilityIdentifier: "command-wheel.profile.name"
                ) { name in
                    await model.perform {
                        try await model.renameProfile(profile.id, to: name)
                    }
                }

                SettingsDivider(leadingInset: 0)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default profile")
                            .commandlyFont(size: 12.5, weight: .medium)
                        Text("Used when no explicit shortcut or application rule selects another profile.")
                            .commandlyFont(size: 10.5)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if model.configuration.defaultProfileID == profile.id {
                        Label("Default", systemImage: "star.fill")
                            .commandlyFont(size: 10, weight: .semibold)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Make Default") {
                            run { try await model.setDefaultProfile(profile.id) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                SettingsDivider(leadingInset: 0)

                CommandWheelAsyncToggle(
                    title: "Enable profile",
                    subtitle: "Disabled profiles are excluded from shortcuts and contextual selection.",
                    value: profile.isEnabled,
                    isDisabled: model.configuration.defaultProfileID == profile.id
                ) { enabled in
                    await model.perform {
                        try await model.setProfileEnabled(enabled, profileID: profile.id)
                    }
                }

                SettingsDivider(leadingInset: 0)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global shortcut")
                            .commandlyFont(size: 12.5, weight: .medium)
                        Text("Carbon registers press and release directly; Accessibility access is not required.")
                            .commandlyFont(size: 10.5)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    ApplicationHotkeyRecorder(
                        hotKey: profile.shortcut,
                        isDisabled: profile.isEnabled == false,
                        accessibilityTitle: "\(profile.name) Command Wheel"
                    ) { shortcut in
                        run { try await model.setShortcut(shortcut, profileID: profile.id) }
                    }
                }

                if let warning = model.shortcutWarning(for: profile.id) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .commandlyFont(size: 10)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("command-wheel.shortcut.warning")
                }

                SettingsDivider(leadingInset: 0)

                permissionStatus

                SettingsDivider(leadingInset: 0)

                CommandWheelPickerRow("Activation") {
                    Picker("Activation", selection: activationBinding) {
                        Text("Hold and release").tag(CommandWheelActivationBehavior.holdAndRelease)
                        Text("Toggle").tag(CommandWheelActivationBehavior.toggle)
                    }
                }

                CommandWheelPickerRow("Placement") {
                    Picker("Placement", selection: placementBinding) {
                        Text("At pointer").tag(CommandWheelPlacementKind.cursor)
                        Text("Active display center").tag(CommandWheelPlacementKind.activeScreenCenter)
                        Text("Fixed display point").tag(CommandWheelPlacementKind.fixed)
                    }
                }

                if case .fixedNormalizedPoint(_, let x, let y) = profile.placement {
                    CommandWheelPickerRow("Display") {
                        Picker("Display", selection: fixedScreenBinding) {
                            Text("Active display").tag(String?.none)
                            ForEach(fixedDisplayOptions) { option in
                                Text(option.title).tag(Optional(option.id))
                            }
                            if let savedIdentifier = fixedScreenIdentifier,
                               fixedDisplayOptions.contains(where: {
                                   $0.id == savedIdentifier
                               }) == false {
                                Text("Saved display unavailable")
                                    .tag(Optional(savedIdentifier))
                            }
                        }
                    }
                    .accessibilityIdentifier("command-wheel.placement.display")

                    CommandWheelSliderRow(
                        title: "Horizontal position",
                        value: x,
                        range: 0 ... 1,
                        step: 0.01,
                        valueLabel: "\(Int((x * 100).rounded()))%"
                    ) { value in
                        await model.perform {
                            try await model.setFixedPlacementCoordinates(
                                x: value,
                                y: y,
                                profileID: profile.id
                            )
                        }
                    }
                    .accessibilityIdentifier("command-wheel.placement.x")

                    CommandWheelSliderRow(
                        title: "Vertical position",
                        value: y,
                        range: 0 ... 1,
                        step: 0.01,
                        valueLabel: "\(Int((y * 100).rounded()))%"
                    ) { value in
                        await model.perform {
                            try await model.setFixedPlacementCoordinates(
                                x: x,
                                y: value,
                                profileID: profile.id
                            )
                        }
                    }
                    .accessibilityIdentifier("command-wheel.placement.y")
                }
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.vertical, 8)
        }
    }

    private var permissionStatus: some View {
        let presentation = model.accessibilityPermissionPresentation(for: permissionState)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(permissionState == .authorized ? .green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(presentation.detail)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Permission Settings", action: onOpenPermissions)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("command-wheel.permissions.open")
        }
        .accessibilityElement(children: .contain)
    }

    private var activationBinding: Binding<CommandWheelActivationBehavior> {
        Binding(
            get: { profile.activationBehavior },
            set: { value in
                run { try await model.setActivationBehavior(value, profileID: profile.id) }
            }
        )
    }

    private var placementBinding: Binding<CommandWheelPlacementKind> {
        Binding(
            get: {
                switch profile.placement {
                case .cursor: return .cursor
                case .activeScreenCenter: return .activeScreenCenter
                case .fixedNormalizedPoint: return .fixed
                }
            },
            set: { kind in
                let placement: CommandWheelPlacement
                switch kind {
                case .cursor: placement = .cursor
                case .activeScreenCenter: placement = .activeScreenCenter
                case .fixed:
                    if case .fixedNormalizedPoint = profile.placement {
                        placement = profile.placement
                    } else {
                        placement = .fixedNormalizedPoint(
                            screenIdentifier: nil,
                            x: 0.5,
                            y: 0.5
                        )
                    }
                }
                run { try await model.setPlacement(placement, profileID: profile.id) }
            }
        )
    }

    private var fixedScreenIdentifier: String? {
        guard case .fixedNormalizedPoint(let identifier, _, _) = profile.placement else {
            return nil
        }
        return identifier
    }

    private var fixedScreenBinding: Binding<String?> {
        Binding(
            get: { fixedScreenIdentifier },
            set: { identifier in
                run {
                    try await model.setFixedPlacementScreenIdentifier(
                        identifier,
                        profileID: profile.id
                    )
                }
            }
        )
    }

    private var fixedDisplayOptions: [CommandWheelDisplayOption] {
        NSScreen.screens.enumerated().map { index, screen in
            let identifier = NSScreenCommandWheelDisplayResolver.identifier(for: screen)
            let suffix = screen == NSScreen.main ? " — Main" : ""
            return CommandWheelDisplayOption(
                id: identifier,
                title: "\(screen.localizedName)\(suffix) · Display \(index + 1)"
            )
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { await model.perform(operation) }
    }
}

private enum CommandWheelPlacementKind: Hashable {
    case cursor
    case activeScreenCenter
    case fixed
}

private struct CommandWheelDisplayOption: Identifiable {
    let id: String
    let title: String
}

private struct CommandWheelBehaviorSection: View {
    @Bindable var model: CommandWheelSettingsModel
    let profile: CommandWheelProfile

    var body: some View {
        SettingsSection("Appearance and Interaction") {
            VStack(spacing: 10) {
                Stepper(value: slotCountBinding, in: 1 ... CommandWheelLimits.maximumVisibleSlots) {
                    CommandWheelSettingLabel(
                        title: "Visible slots",
                        value: "\(profile.interaction.visibleSlotCount)"
                    )
                }
                .accessibilityIdentifier("command-wheel.slot-count")

                CommandWheelSliderRow(
                    title: "Wheel radius",
                    value: profile.appearance.wheelRadius,
                    range: CommandWheelLimits.minimumWheelRadius
                        ... CommandWheelLimits.maximumWheelRadius,
                    step: 2,
                    valueLabel: "\(Int(profile.appearance.wheelRadius)) pt"
                ) { value in
                    await model.perform {
                        try await model.setWheelRadius(value, profileID: profile.id)
                    }
                }

                CommandWheelSliderRow(
                    title: "Dead zone",
                    value: profile.interaction.deadZoneRadius,
                    range: 0 ... max(0, profile.interaction.selectionRadius - 1),
                    step: 1,
                    valueLabel: "\(Int(profile.interaction.deadZoneRadius)) pt"
                ) { value in
                    await model.perform {
                        try await model.setDeadZoneRadius(value, profileID: profile.id)
                    }
                }

                CommandWheelAsyncToggle(
                    title: "Click selection",
                    subtitle: "Allow clicking a segment to run or open it.",
                    value: profile.interaction.allowsClickSelection
                ) { value in
                    await model.perform {
                        try await model.setClickSelectionEnabled(value, profileID: profile.id)
                    }
                }

                CommandWheelAsyncToggle(
                    title: "Keyboard selection",
                    subtitle: "Expose numbered keyboard alternatives for every visible slot.",
                    value: profile.interaction.allowsKeyboardSelection
                ) { value in
                    await model.perform {
                        try await model.setKeyboardSelectionEnabled(value, profileID: profile.id)
                    }
                }

                CommandWheelPickerRow("Submenu activation") {
                    Picker("Submenu activation", selection: submenuBinding) {
                        Text("Directional continuation")
                            .tag(CommandWheelSubmenuActivationBehavior.directionalContinuation)
                        Text("Dwell").tag(CommandWheelSubmenuActivationBehavior.dwell)
                        Text("Click only").tag(CommandWheelSubmenuActivationBehavior.clickOnly)
                        Text("Disabled").tag(CommandWheelSubmenuActivationBehavior.disabled)
                    }
                }

                if profile.interaction.submenuActivationBehavior == .dwell {
                    CommandWheelSliderRow(
                        title: "Submenu dwell",
                        value: profile.interaction.submenuDwellDurationSeconds,
                        range: 0.1 ... 2,
                        step: 0.05,
                        valueLabel: String(
                            format: "%.2f s",
                            profile.interaction.submenuDwellDurationSeconds
                        )
                    ) { value in
                        await model.perform {
                            try await model.setSubmenuDwellDuration(value, profileID: profile.id)
                        }
                    }
                }

                CommandWheelPickerRow("Animation") {
                    Picker("Animation", selection: animationBinding) {
                        Text("Follow system").tag(CommandWheelAnimationPreference.system)
                        Text("Reduced").tag(CommandWheelAnimationPreference.reduced)
                        Text("Off").tag(CommandWheelAnimationPreference.disabled)
                    }
                }

                HStack(spacing: 20) {
                    Toggle("Keyboard hints", isOn: hintsBinding)
                    Toggle("Hide unavailable", isOn: unavailableBinding)
                    Spacer()
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                SettingsDivider(leadingInset: 0)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interaction defaults")
                            .commandlyFont(size: 12.5, weight: .medium)
                        Text("Reset slot count, dead zone, selection thresholds, click and keyboard input, and submenu timing.")
                            .commandlyFont(size: 10.5)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Reset Interaction") {
                        Task {
                            await model.perform {
                                try await model.resetInteractionDefaults(profileID: profile.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("command-wheel.interaction.reset")
                }
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.vertical, 8)
        }
    }

    private var slotCountBinding: Binding<Int> {
        Binding(
            get: { profile.interaction.visibleSlotCount },
            set: { count in
                run { try await model.setSlotCount(count, profileID: profile.id) }
            }
        )
    }

    private var submenuBinding: Binding<CommandWheelSubmenuActivationBehavior> {
        Binding(
            get: { profile.interaction.submenuActivationBehavior },
            set: { behavior in
                run { try await model.setSubmenuBehavior(behavior, profileID: profile.id) }
            }
        )
    }

    private var animationBinding: Binding<CommandWheelAnimationPreference> {
        Binding(
            get: { profile.appearance.animationPreference },
            set: { value in
                run { try await model.setAnimationPreference(value, profileID: profile.id) }
            }
        )
    }

    private var hintsBinding: Binding<Bool> {
        Binding(
            get: { profile.appearance.showsKeyboardHints },
            set: { value in
                run { try await model.setKeyboardHintsVisible(value, profileID: profile.id) }
            }
        )
    }

    private var unavailableBinding: Binding<Bool> {
        Binding(
            get: { profile.hidesUnavailableSegments },
            set: { value in
                run { try await model.setUnavailableSegmentsHidden(value, profileID: profile.id) }
            }
        )
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { await model.perform(operation) }
    }
}

private struct CommandWheelContextRulesSection: View {
    @Bindable var model: CommandWheelSettingsModel
    let profile: CommandWheelProfile
    @State private var bundleIdentifier = ""
    @State private var priority = 0

    var body: some View {
        SettingsSection(
            "Application Context",
            footer: "Rules match the exact frontmost application bundle identifier. Higher priority wins. Equal app-and-priority pairs are rejected."
        ) {
            VStack(spacing: 10) {
                CommandWheelAsyncToggle(
                    title: "Context-aware profile selection",
                    subtitle: "Allow enabled rules to select a profile when the wheel opens.",
                    value: model.configuration.contextAwareProfileSelectionEnabled
                ) { value in
                    await model.perform {
                        try await model.setContextSelectionEnabled(value)
                    }
                }

                ForEach(profile.contextRules) { rule in
                    SettingsDivider(leadingInset: 0)
                    CommandWheelContextRuleRow(model: model, rule: rule)
                }

                SettingsDivider(leadingInset: 0)

                HStack(spacing: 8) {
                    TextField("com.example.application", text: $bundleIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Application bundle identifier")
                    Stepper("Priority \(priority)", value: $priority, in: -100 ... 100)
                        .fixedSize()
                    Button("Add Rule") { addRule() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(bundleIdentifier.isEmpty || conflictMessage != nil)
                }

                if let conflictMessage {
                    Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                        .commandlyFont(size: 10)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.vertical, 8)
        }
    }

    private var conflictMessage: String? {
        model.contextConflictMessage(
            bundleIdentifier: bundleIdentifier,
            priority: priority
        )
    }

    private func addRule() {
        let bundle = bundleIdentifier
        let nextPriority = priority
        Task {
            await model.perform {
                try await model.addContextRule(
                    bundleIdentifier: bundle,
                    priority: nextPriority
                )
                bundleIdentifier = ""
                priority = 0
            }
        }
    }
}

private struct CommandWheelContextRuleRow: View {
    @Bindable var model: CommandWheelSettingsModel
    let rule: CommandWheelContextRule
    @State private var bundleIdentifier: String
    @State private var priority: Int
    @State private var isEnabled: Bool

    init(model: CommandWheelSettingsModel, rule: CommandWheelContextRule) {
        self.model = model
        self.rule = rule
        _bundleIdentifier = State(initialValue: rule.frontmostApplicationBundleIdentifier)
        _priority = State(initialValue: rule.priority)
        _isEnabled = State(initialValue: rule.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel("Enable context rule")
                TextField("Bundle identifier", text: $bundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                Stepper("Priority \(priority)", value: $priority, in: -100 ... 100)
                    .fixedSize()
                Button("Apply") { apply() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(conflictMessage != nil)
                Button(role: .destructive) {
                    Task {
                        await model.perform {
                            try await model.deleteContextRule(rule.id)
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete context rule")
            }
            if let conflictMessage {
                Text(conflictMessage)
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityIdentifier("command-wheel.context-rule.\(rule.id.uuidString)")
    }

    private var conflictMessage: String? {
        guard isEnabled else { return nil }
        return model.contextConflictMessage(
            bundleIdentifier: bundleIdentifier,
            priority: priority,
            excluding: rule.id
        )
    }

    private func apply() {
        Task {
            await model.perform {
                try await model.updateContextRule(
                    rule.id,
                    bundleIdentifier: bundleIdentifier,
                    priority: priority,
                    isEnabled: isEnabled
                )
            }
        }
    }
}

private struct CommandWheelNameEditor: View {
    let title: String
    let value: String
    let accessibilityIdentifier: String
    let onSave: @MainActor (String) async -> Void
    @State private var draft: String

    init(
        title: String,
        value: String,
        accessibilityIdentifier: String,
        onSave: @escaping @MainActor (String) async -> Void
    ) {
        self.title = title
        self.value = value
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSave = onSave
        _draft = State(initialValue: value)
    }

    var body: some View {
        HStack {
            Text(title)
                .commandlyFont(size: 12.5, weight: .medium)
            Spacer()
            TextField(title, text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(save)
                .accessibilityIdentifier(accessibilityIdentifier)
            Button("Save", action: save)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(draft == value)
        }
        .onChange(of: value) { _, newValue in draft = newValue }
    }

    private func save() {
        Task { await onSave(draft) }
    }
}

private struct CommandWheelAsyncToggle: View {
    let title: String
    let subtitle: String
    let value: Bool
    var isDisabled = false
    let onChange: @MainActor (Bool) async -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                Task { await onChange(newValue) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .commandlyFont(size: 12.5, weight: .medium)
                Text(subtitle)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(isDisabled)
    }
}

private struct CommandWheelPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack {
            Text(title)
                .commandlyFont(size: 12.5, weight: .medium)
            Spacer()
            content()
                .labelsHidden()
                .frame(width: 230)
        }
    }
}

private struct CommandWheelSettingLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .commandlyFont(size: 12.5, weight: .medium)
            Spacer()
            Text(value)
                .commandlyFont(size: 10.5, design: .monospaced)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CommandWheelSliderRow: View {
    let title: String
    let sourceValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: String
    let onCommit: @MainActor (Double) async -> Void
    @State private var draftValue: Double

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: String,
        onCommit: @escaping @MainActor (Double) async -> Void
    ) {
        self.title = title
        self.sourceValue = value
        self.range = range
        self.step = step
        self.valueLabel = valueLabel
        self.onCommit = onCommit
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: 4) {
            CommandWheelSettingLabel(title: title, value: valueLabel)
            Slider(
                value: $draftValue,
                in: range,
                step: step,
                onEditingChanged: { editing in
                    guard editing == false else { return }
                    Task { await onCommit(draftValue) }
                }
            )
        }
        .onChange(of: sourceValue) { _, newValue in draftValue = newValue }
    }
}
