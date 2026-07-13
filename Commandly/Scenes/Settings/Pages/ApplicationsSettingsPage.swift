import CommandKit
import DesignSystem
import SwiftUI

struct ApplicationsSettingsPage: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPageHeader(
                title: "Applications",
                subtitle: "Configure how registered applications are discovered and opened."
            )

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ApplicationsToolbar(model: model)

                    Divider()
                        .overlay(SettingsPalette.border)

                    ApplicationHierarchy(model: model)
                }
                    .frame(width: ApplicationTableLayout.tableWidth)

                Divider()
                    .overlay(SettingsPalette.border)

                ApplicationSettingsInspector(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SettingsPalette.card.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SettingsPalette.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        }
        .padding(.horizontal, 28)
        .padding(.top, Spacing.md.rawValue)
        .padding(.bottom, 22)
    }
}

private struct ApplicationsToolbar: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        HStack(spacing: 10) {
            ApplicationsSearchField(query: $model.query)
                .frame(width: 250)

            Menu {
                Button("All Types") {
                    model.kindFilter = nil
                }

                Divider()

                ForEach(LauncherApplicationKind.allCases) { kind in
                    Button(kind.title) {
                        model.kindFilter = kind
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .commandlyFont(size: 9.5, weight: .semibold)
                    Text(model.kindFilter?.title ?? "All Types")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .commandlyFont(size: 7.5, weight: .semibold)
                }
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(model.kindFilter == nil ? Color.secondary : BrandPalette.accentSoft)
                .padding(.horizontal, 9)
                .frame(width: 132, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            model.kindFilter == nil
                                ? SettingsPalette.border
                                : BrandPalette.accent.opacity(0.28),
                            lineWidth: 1
                        )
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Filter applications by type")
            .accessibilityLabel("Application type filter")
            .accessibilityValue(model.kindFilter?.title ?? "All Types")

            Spacer()

            Text("\(model.rows.count) items")
                .commandlyFont(size: 10.5)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color.primary.opacity(0.018))
    }
}

private struct ApplicationsSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(isFocused ? BrandPalette.accentSoft : Color.secondary)

            TextField("Search applications", text: $query)
                .textFieldStyle(.plain)
                .commandlyFont(size: 11)
                .focused($isFocused)

            if query.isEmpty == false {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .commandlyFont(size: 10)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear application search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isFocused ? 0.065 : 0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused ? BrandPalette.accent.opacity(0.42) : SettingsPalette.border,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isFocused)
    }
}

private struct ApplicationHierarchy: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(SettingsPalette.border)

            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No applications found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different name, alias, or type.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.rows) { row in
                            ApplicationHierarchyRow(
                                row: row,
                                isSelected: model.selectedID == row.id,
                                onSelect: { model.select(row.id) },
                                onToggleExpansion: { model.toggleExpansion(row.id) },
                                onAliasChange: { model.setAlias($0, for: row.id) },
                                onHotKeyChange: { model.setHotKey($0, for: row.id) },
                                hotkeyIssue: model.hotkeyIssue(for: row.id),
                                onEnabledChange: { model.setEnabled($0, for: row.id) }
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Type").frame(width: ApplicationTableLayout.typeWidth, alignment: .leading)
            Text("Alias").frame(width: ApplicationTableLayout.aliasWidth, alignment: .leading)
            Text("Shortcut").frame(width: ApplicationTableLayout.shortcutWidth, alignment: .leading)
            Text("Enabled").frame(width: ApplicationTableLayout.enabledWidth, alignment: .center)
        }
        .commandlyFont(size: 9.5, weight: .semibold)
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.45)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(Color.primary.opacity(0.018))
    }
}

private struct ApplicationHierarchyRow: View {
    let row: LauncherApplicationSettingsRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleExpansion: () -> Void
    let onAliasChange: (String) -> Void
    let onHotKeyChange: (LauncherHotKey?) -> Void
    let hotkeyIssue: String?
    let onEnabledChange: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Color.clear.frame(width: CGFloat(row.depth) * 13)
                Button(action: onToggleExpansion) {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .commandlyFont(size: 8, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .opacity(row.hasChildren ? 1 : 0)
                        .frame(width: 14, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(row.hasChildren == false)
                .accessibilityLabel(
                    row.isExpanded
                        ? "Collapse \(row.definition.title)"
                        : "Expand \(row.definition.title)"
                )

                Image(systemName: row.definition.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? BrandPalette.accentSoft : .secondary)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isSelected
                                    ? BrandPalette.accent.opacity(0.14)
                                    : Color.primary.opacity(0.04)
                            )
                    }

                Text(row.definition.title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ApplicationKindBadge(kind: row.definition.kind)
                .frame(width: ApplicationTableLayout.typeWidth, alignment: .leading)

            if row.definition.kind == .group {
                unavailableValue
                    .frame(width: ApplicationTableLayout.aliasWidth, alignment: .leading)
            } else {
                InlineAliasEditor(
                    applicationTitle: row.definition.title,
                    alias: row.settings.alias,
                    onCommit: onAliasChange
                )
                .frame(width: ApplicationTableLayout.aliasWidth)
            }

            if row.definition.kind == .group {
                unavailableValue
                    .frame(width: ApplicationTableLayout.shortcutWidth, alignment: .leading)
            } else {
                HStack(spacing: 4) {
                    ApplicationHotkeyRecorder(
                        hotKey: row.settings.hotKey,
                        isDisabled: row.settings.isEnabled == false,
                        accessibilityTitle: row.definition.title,
                        onChange: onHotKeyChange
                    )

                    if let hotkeyIssue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .commandlyFont(size: 9.5, weight: .semibold)
                            .foregroundStyle(.orange)
                            .help(hotkeyIssue)
                            .accessibilityLabel(hotkeyIssue)
                    }
                }
                .frame(width: ApplicationTableLayout.shortcutWidth, alignment: .leading)
            }

            Toggle("", isOn: Binding(
                get: { row.settings.isEnabled },
                set: { onEnabledChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(width: ApplicationTableLayout.enabledWidth)
            .accessibilityLabel("Enable \(row.definition.title)")
        }
        .commandlyFont(size: 10.5, weight: isSelected ? .medium : .regular)
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(BrandPalette.accentSoft)
                    .frame(width: 2.5, height: 18)
                    .padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .focusable()
        .onKeyPress(.return) {
            onSelect()
            return .handled
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                isHovered = hovering
            }
        }
        .opacity(row.isEffectivelyEnabled ? 1 : 0.58)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select") { onSelect() }
    }

    private var unavailableValue: some View {
        Text("—")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var rowBackground: Color {
        if isSelected {
            return BrandPalette.accent.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.045)
        }
        if row.definition.kind == .group {
            return Color.primary.opacity(0.022)
        }
        return .clear
    }
}

private struct ApplicationKindBadge: View {
    let kind: LauncherApplicationKind

    var body: some View {
        Text(kind.title)
            .commandlyFont(size: 9, weight: .semibold)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.045))
            }
            .overlay {
                Capsule()
                    .strokeBorder(SettingsPalette.border.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct InlineAliasEditor: View {
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
        TextField("Alias", text: $draft)
            .textFieldStyle(.plain)
            .commandlyFont(size: 10.5)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isFocused ? 0.065 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isFocused ? BrandPalette.accent.opacity(0.4) : SettingsPalette.border,
                        lineWidth: 1
                    )
            }
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if focused == false { commit() }
            }
            .onChange(of: alias) { _, newValue in
                if isFocused == false { draft = newValue }
            }
            .accessibilityLabel("Alias for \(applicationTitle)")
            .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isFocused)
    }

    private func commit() {
        guard draft != alias else { return }
        onCommit(draft)
    }
}

private enum ApplicationTableLayout {
    static let tableWidth: CGFloat = 650
    static let typeWidth: CGFloat = 86
    static let aliasWidth: CGFloat = 132
    static let shortcutWidth: CGFloat = 138
    static let enabledWidth: CGFloat = 52
}

#Preview {
    ApplicationsSettingsPage(
        model: LauncherApplicationsSettingsModel(
            registry: .makeBuiltIn()
        )
    )
    .frame(width: 1_092, height: 720)
}
