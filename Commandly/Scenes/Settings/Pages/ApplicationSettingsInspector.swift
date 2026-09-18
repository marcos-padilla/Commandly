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
                            configurationSections(definition)
                        }

                        let commands = model.commands(for: definition.id)
                        if commands.isEmpty == false {
                            commandSection(commands)
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
            InspectorTagsEditor(
                itemTitle: definition.title,
                builtInTags: definition.defaultTags,
                customTags: model.selectedPreferences.tags
                    ?? (settings.alias.isEmpty ? [] : [settings.alias]),
                onChange: { model.setTags($0, for: definition.id) }
            )

            if definition.kind != .command {
                InspectorFieldDivider()

                InspectorFieldRow(
                    title: "Global shortcut",
                    description: model.hotkeyDescription(for: definition.id)
                ) {
                    HStack(spacing: 6) {
                        ApplicationHotkeyRecorder(
                            hotKey: settings.hotKey,
                            isDisabled: model.selectedIsEffectivelyEnabled == false,
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
    }

    @ViewBuilder
    private func coreSettings(
        definition: LauncherApplicationDefinition,
        settings: LauncherApplicationResolvedSettings
    ) -> some View {
        InspectorSection(title: "Availability") {
            InspectorToggleRow(
                title: "Enabled",
                description: availabilityDescription(
                    definition: definition,
                    settings: settings
                ),
                isOn: Binding(
                    get: { settings.isEnabled },
                    set: { model.setEnabled($0, for: definition.id) }
                )
            )
        }
    }

    private func availabilityDescription(
        definition: LauncherApplicationDefinition,
        settings: LauncherApplicationResolvedSettings
    ) -> String {
        if definition.kind == .group {
            return "Disabling this group also disables every item beneath it."
        }
        if settings.isEnabled, model.selectedIsEffectivelyEnabled == false {
            return "This item is enabled here, but a parent application or group is disabled."
        }
        return "Disabled applications and tools do not appear in search or respond to shortcuts."
    }

    private func commandSection(
        _ commands: [LauncherApplicationCommandDefinition]
    ) -> some View {
        InspectorSection(title: "Typed Commands") {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                if index > 0 { InspectorFieldDivider() }
                VStack(alignment: .leading, spacing: 5) {
                    Text(command.title)
                        .commandlyFont(size: 11.5, weight: .medium)
                    Text(command.syntax)
                        .commandlyFont(size: 10.5, design: .monospaced)
                        .textSelection(.enabled)
                    if command.examples.isEmpty == false {
                        Text("Example: \(command.examples.joined(separator: ", "))")
                            .commandlyFont(size: 10)
                            .foregroundStyle(.tertiary)
                    }
                    Text("Commands invoke the tool above and do not have separate shortcuts.")
                        .commandlyFont(size: 10)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func configurationSections(_ definition: LauncherApplicationDefinition) -> some View {
        ForEach(ConfigurationFieldSection.grouping(definition.configurationFields)) { section in
            InspectorSection(title: section.title) {
                ForEach(Array(section.fields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 { InspectorFieldDivider() }
                    LauncherConfigurationFieldEditor(
                        field: field,
                        value: model.selectedSettings?.value(for: field.variable)
                            ?? field.defaultValue,
                        onChange: {
                            model.setConfiguration(
                                $0,
                                variable: field.variable,
                                for: definition.id
                            )
                        }
                    )
                }
            }
        }
    }
}

private struct ConfigurationFieldSection: Identifiable {
    let id: String
    let title: String
    var fields: [LauncherConfigurationField]

    static func grouping(
        _ fields: [LauncherConfigurationField]
    ) -> [ConfigurationFieldSection] {
        var sections: [ConfigurationFieldSection] = []
        for field in fields {
            let declaredTitle = field.section?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = declaredTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Configuration"
            if let index = sections.firstIndex(where: { $0.id == title }) {
                sections[index].fields.append(field)
            } else {
                sections.append(
                    ConfigurationFieldSection(id: title, title: title, fields: [field])
                )
            }
        }
        return sections
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

private struct InspectorTagsEditor: View {
    let itemTitle: String
    let builtInTags: [String]
    let customTags: [String]
    let onChange: ([String]) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Tags")
                    .commandlyFont(size: 11.5, weight: .medium)
                Spacer()
                Text("\(builtInTags.count + customTags.count)")
                    .commandlyFont(size: 9.5, design: .rounded)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(
                        "\(builtInTags.count + customTags.count) search tags"
                    )
            }

            if builtInTags.isEmpty == false || customTags.isEmpty == false {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(builtInTags, id: \.self) { tag in
                            TagCapsule(title: tag, isBuiltIn: true, onRemove: nil)
                        }
                        ForEach(customTags, id: \.self) { tag in
                            TagCapsule(
                                title: tag,
                                isBuiltIn: false,
                                onRemove: {
                                    onChange(customTags.filter { $0 != tag })
                                }
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 6) {
                TextField("Add a tag", text: $draft)
                    .textFieldStyle(.plain)
                    .inspectorInputStyle(width: 190)
                    .onSubmit(addTag)
                    .accessibilityLabel("Add search tag for \(itemTitle)")

                Button(action: addTag) {
                    Image(systemName: "plus")
                        .commandlyFont(size: 9, weight: .semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add tag to \(itemTitle)")
            }

            Text("Built-in tags stay available; add your own alternate words or phrases.")
                .commandlyFont(size: 10)
                .foregroundStyle(.tertiary)
        }
    }

    private func addTag() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return }
        onChange(customTags + [value])
        draft = ""
    }
}

private struct TagCapsule: View {
    let title: String
    let isBuiltIn: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .commandlyFont(size: 9.5, weight: .medium)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .commandlyFont(size: 7.5, weight: .bold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title) tag")
            } else if isBuiltIn {
                Image(systemName: "lock.fill")
                    .commandlyFont(size: 6.5, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Built-in")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 23)
        .background(
            SettingsVisualStyle.fieldBackground,
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(SettingsVisualStyle.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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

struct InspectorFieldRow<Control: View>: View {
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

extension View {
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
