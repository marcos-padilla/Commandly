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
                    VStack(alignment: .leading, spacing: 20) {
                        ApplicationInspectorHeader(definition: definition)
                        coreSettings(definition: definition, settings: settings)

                        if definition.configurationFields.isEmpty == false {
                            configurationFields(definition)
                        }

                        Button {
                            model.resetSelectedApplication()
                        } label: {
                            Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                                .commandlyFont(size: 10.5, weight: .medium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                        .help("Restore this application's default settings")
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Select an application",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose a registered item to inspect its settings.")
                )
            }
        }
        .background(Color.primary.opacity(0.012))
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
            ForEach(definition.configurationFields) { field in
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
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: definition.systemImage)
                .symbolRenderingMode(.hierarchical)
                .commandlyFont(size: 20, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BrandPalette.accent.opacity(0.18), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(definition.title)
                    .commandlyFont(size: 16, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(definition.kind.title)
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background {
                        Capsule()
                            .fill(BrandPalette.accent.opacity(0.1))
                    }
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .commandlyFont(size: 9, weight: .semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.7)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.028))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(SettingsPalette.border.opacity(0.78), lineWidth: 1)
            }
        }
    }
}

private struct InspectorToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        InspectorFieldRow(title: title, description: description) {
            Toggle("", isOn: $isOn)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .commandlyFont(size: 11.5, weight: .medium)
                Spacer(minLength: 8)
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
        case .toggle:
            Toggle(
                "",
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
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(SettingsPalette.border, lineWidth: 1)
            }
    }
}
