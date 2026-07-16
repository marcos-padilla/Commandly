import CommandKit
import DesignSystem
import SwiftUI

struct ApplicationsSettingsPage: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ApplicationsToolbar(model: model)

                Divider()
                    .overlay(SettingsVisualStyle.separator)

                ApplicationHierarchy(model: model)
            }
            .frame(minWidth: 290, idealWidth: 316, maxWidth: 340)
            .background(SettingsVisualStyle.sidebarBackground.opacity(0.38))

            Divider()
                .overlay(SettingsVisualStyle.separator)

            ApplicationSettingsInspector(model: model)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsVisualStyle.detailBackground)
    }
}

private struct ApplicationsToolbar: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            ApplicationsSearchField(query: $model.query)
                .frame(maxWidth: .infinity)

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
                Image(systemName: "line.3.horizontal.decrease")
                    .symbolVariant(model.kindFilter == nil ? .none : .fill)
                    .commandlyFont(size: 11, weight: .semibold)
                    .foregroundStyle(model.kindFilter == nil ? Color.secondary : Color.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Filter applications by type")
            .accessibilityLabel("Application type filter")
            .accessibilityValue(model.kindFilter?.title ?? "All Types")

            Text("\(model.rows.count)")
                .commandlyFont(size: 10, weight: .medium, design: .rounded)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .accessibilityLabel("\(model.rows.count) items")
        }
        .padding(.horizontal, Spacing.sm.rawValue)
        .frame(height: 48)
    }
}

private struct ApplicationsSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(isFocused ? Color.primary : Color.secondary)
                .accessibilityHidden(true)

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
        .frame(height: 29)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(
                    isFocused ? SettingsVisualStyle.focusRing : SettingsVisualStyle.separator,
                    lineWidth: 1
                )
        }
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: CornerRadius.md.rawValue)
        )
        .animation(reduceMotion ? nil : CommandlyMotion.hover, value: isFocused)
    }
}

private struct ApplicationHierarchy: View {
    @Bindable var model: LauncherApplicationsSettingsModel

    var body: some View {
        Group {
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
                                hotkeyIssue: model.hotkeyIssue(for: row.id),
                                onEnabledChange: { model.setEnabled($0, for: row.id) }
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ApplicationHierarchyRow: View {
    let row: LauncherApplicationSettingsRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleExpansion: () -> Void
    let hotkeyIssue: String?
    let onEnabledChange: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 12)

            Button(action: onToggleExpansion) {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .commandlyFont(size: 8, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .opacity(row.hasChildren ? 1 : 0)
                    .frame(width: 14, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(row.hasChildren == false)
            .accessibilityHidden(row.hasChildren == false)
            .accessibilityLabel(
                row.isExpanded
                    ? "Collapse \(row.definition.title)"
                    : "Expand \(row.definition.title)"
            )

            Button(action: onSelect) {
                HStack(spacing: 8) {
                    settingsGlyph(
                        row.definition.systemImage,
                        emphasized: isSelected,
                        size: 20
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.definition.title)
                            .commandlyFont(size: 11.5, weight: isSelected ? .semibold : .medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            ApplicationKindBadge(kind: row.definition.kind)
                            if row.definition.kind != .group, row.settings.alias.isEmpty == false {
                                Text(row.settings.alias)
                                    .commandlyFont(size: 9.5, design: .rounded)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    if let hotkeyIssue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .commandlyFont(size: 9.5, weight: .semibold)
                            .foregroundStyle(.orange)
                            .help(hotkeyIssue)
                            .accessibilityLabel(hotkeyIssue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.definition.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Toggle("", isOn: Binding(
                get: { row.settings.isEnabled },
                set: { onEnabledChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("Enable \(row.definition.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .fill(rowBackground)
        }
        .animation(CommandlyMotion.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .opacity(row.isEffectivelyEnabled ? 1 : 0.58)
    }

    private var rowBackground: Color {
        if isSelected { return SettingsVisualStyle.selection }
        if isHovered { return SettingsVisualStyle.hover }
        return .clear
    }

    private var accessibilityValue: String {
        var parts = [row.definition.kind.title]
        if row.settings.alias.isEmpty == false {
            parts.append("Alias \(row.settings.alias)")
        }
        if let hotkeyIssue {
            parts.append(hotkeyIssue)
        }
        return parts.joined(separator: ", ")
    }
}

private struct ApplicationKindBadge: View {
    let kind: LauncherApplicationKind

    var body: some View {
        Text(kind.title)
            .commandlyFont(size: 8.5, weight: .medium)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

#Preview {
    ApplicationsSettingsPage(
        model: LauncherApplicationsSettingsModel(
            registry: .makeBuiltIn()
        )
    )
    .frame(width: 900, height: 660)
}
