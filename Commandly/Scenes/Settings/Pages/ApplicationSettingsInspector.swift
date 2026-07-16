import CommandKit
import DesignSystem
import SwiftUI

struct ApplicationSettingsInspector: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        Group {
            if let definition = model.selectedDefinition,
               let settings = model.selectedSettings {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg.rawValue) {
                        ApplicationInspectorHeader(definition: definition)
                        coreSettings(definition: definition, settings: settings)

                        if definition.kind != .group {
                            discoverySettings(definition: definition, settings: settings)
                        }

                        if definition.configurationFields.isEmpty == false {
                            configurationFields(definition)
                        }

                        Button {
                            model.resetSelectedApplication()
                        } label: {
                            Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                                .commandlyFont(size: 10.5, weight: .medium)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                        .help("Restore this application's default settings")
                    }
                    .frame(maxWidth: 660, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Spacing.lg.rawValue)
                }
                .id(definition.id)
            } else {
                ContentUnavailableView(
                    "Select an application",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose a registered item to inspect its settings.")
                )
            }
        }
        .background(SettingsVisualStyle.detailBackground)
    }

    private func discoverySettings(
        definition: LauncherApplicationDefinition,
        settings: LauncherApplicationResolvedSettings
    ) -> some View {
        InspectorSection(title: "Discovery & Shortcut") {
            InspectorAliasEditor(
                applicationTitle: definition.title,
                alias: settings.alias,
                onCommit: { model.setAlias($0, for: definition.id) }
            )

            InspectorFieldDivider()

            InspectorFieldRow(
                title: "Global shortcut",
                description: "Open this application directly from anywhere."
            ) {
                HStack(spacing: 6) {
                    ApplicationHotkeyRecorder(
                        hotKey: settings.hotKey,
                        isDisabled: settings.isEnabled == false,
                        accessibilityTitle: definition.title,
                        onChange: { model.setHotKey($0, for: definition.id) }
                    )

                    if let issue = model.hotkeyIssue(for: definition.id) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .commandlyFont(size: 9.5, weight: .semibold)
                            .foregroundStyle(.orange)
                            .help(issue)
                            .accessibilityLabel(issue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coreSettings(
        definition: LauncherApplicationDefinition,
        settings: LauncherApplicationResolvedSettings
    ) -> some View {
        InspectorSection(title: "Availability") {
            InspectorToggleRow(
                title: "Enabled",
                description: definition.kind == .group
                    ? "Disabling this group also disables every item beneath it."
                    : "Disabled applications do not appear in search or respond to hotkeys.",
                isOn: Binding(
                    get: { settings.isEnabled },
                    set: { model.setEnabled($0, for: definition.id) }
                )
            )
        }
    }

    private func configurationFields(_ definition: LauncherApplicationDefinition) -> some View {
        InspectorSection(title: "Configuration") {
            ForEach(Array(definition.configurationFields.enumerated()), id: \.element.id) {
                index, field in
                if index > 0 { InspectorFieldDivider() }
                LauncherConfigurationFieldEditor(
                    field: field,
                    value: model.selectedSettings?.value(for: field.variable) ?? field.defaultValue,
                    onChange: {
                        model.setConfiguration($0, variable: field.variable, for: definition.id)
                    }
                )
            }
        }
    }
}

private struct ApplicationInspectorHeader: View {
    let definition: LauncherApplicationDefinition

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm.rawValue) {
            settingsGlyph(
                definition.systemImage,
                emphasized: true,
                size: 32
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(definition.title)
                    .commandlyFont(size: 16, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(definition.kind.title)
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(.secondary)
                if let subtitle = definition.subtitle {
                    Text(subtitle)
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            Text(title)
                .commandlyFont(size: 10.5, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Divider()
                .overlay(SettingsVisualStyle.separator)

            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                content()
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InspectorFieldDivider: View {
    var body: some View {
        Divider()
            .overlay(SettingsVisualStyle.separator)
    }
}

private struct InspectorAliasEditor: View {
    let applicationTitle: String
    let alias: String
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        applicationTitle: String,
        alias: String,
        onCommit: @escaping (String) -> Void
    ) {
        self.applicationTitle = applicationTitle
        self.alias = alias
        self.onCommit = onCommit
        _draft = State(initialValue: alias)
    }

    var body: some View {
        InspectorFieldRow(
            title: "Alias",
            description: "Use this alternate name when searching Commandly."
        ) {
            TextField("Alias", text: $draft)
                .textFieldStyle(.plain)
                .inspectorInputStyle(width: 150)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in
                    if focused == false { commit() }
                }
                .onChange(of: alias) { _, newValue in
                    if isFocused == false { draft = newValue }
                }
                .accessibilityLabel("Alias for \(applicationTitle)")
        }
    }

    private func commit() {
        guard draft != alias else { return }
        onCommit(draft)
    }
}

private struct InspectorToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        InspectorFieldRow(title: title, description: description) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct InspectorFieldRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: Spacing.xs.rawValue) {
                Text(title)
                    .commandlyFont(size: 11.5, weight: .medium)
                Spacer(minLength: Spacing.xs.rawValue)
                control()
            }
            if let description {
                Text(description)
                    .commandlyFont(size: 10)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LauncherConfigurationFieldEditor: View {
    let field: LauncherConfigurationField
    let value: LauncherConfigurationValue
    let onChange: (LauncherConfigurationValue) -> Void

    var body: some View {
        InspectorFieldRow(title: field.title, description: field.description) {
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch field.kind {
        case .text:
            TextField(
                field.placeholder ?? "Value",
                text: Binding(
                    get: { value.textValue ?? "" },
                    set: { onChange(.text($0)) }
                )
            )
            .textFieldStyle(.plain)
            .inspectorInputStyle(width: 140)
            .accessibilityLabel(field.title)
        case .toggle:
            Toggle(
                field.title,
                isOn: Binding(
                    get: { value.booleanValue ?? false },
                    set: { onChange(.boolean($0)) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        case .integer:
            TextField(
                field.placeholder ?? "0",
                value: Binding(
                    get: { value.integerValue ?? 0 },
                    set: { onChange(.integer($0)) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .inspectorInputStyle(width: 88)
            .accessibilityLabel(field.title)
        case .decimal:
            TextField(
                field.placeholder ?? "0",
                value: Binding(
                    get: { value.decimalValue ?? 0 },
                    set: { onChange(.decimal($0)) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .inspectorInputStyle(width: 88)
            .accessibilityLabel(field.title)
        case .selection:
            Picker(
                field.title,
                selection: Binding(
                    get: { value.textValue ?? field.options.first?.id ?? "" },
                    set: { onChange(.text($0)) }
                )
            ) {
                ForEach(field.options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }
}

private extension View {
    func inspectorInputStyle(width: CGFloat) -> some View {
        padding(.horizontal, 8)
            .frame(width: width, height: 27)
            .background(
                SettingsVisualStyle.fieldBackground,
                in: RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                    .strokeBorder(SettingsVisualStyle.separator, lineWidth: 1)
            }
    }
}
