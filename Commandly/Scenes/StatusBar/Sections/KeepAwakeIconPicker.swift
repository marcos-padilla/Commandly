import DesignSystem
import SwiftUI

/// Chooses the glyph and tint the menu bar shows while a Keep Awake session runs.
struct KeepAwakeIconPicker: View {
    @Binding var icon: KeepAwakeActiveIcon
    @Binding var tint: KeepAwakeIconTint

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            choiceHeader("Active icon", value: icon.title)

            HStack(spacing: 5) {
                ForEach(KeepAwakeActiveIcon.allCases) { choice in
                    iconButton(choice)
                }
            }

            choiceHeader("Active icon color", value: tint.title)

            HStack(spacing: 6) {
                ForEach(KeepAwakeIconTint.allCases) { choice in
                    tintButton(choice)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LauncherPalette.hover)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu bar icon while awake")
    }

    private func choiceHeader(_ title: String, value: String) -> some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text(title)
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs.rawValue)
            Text(value)
                .commandlyFont(size: 10)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func iconButton(_ choice: KeepAwakeActiveIcon) -> some View {
        let isSelected = choice == icon
        return Button {
            icon = choice
        } label: {
            Image(systemName: choice.symbolName)
                .commandlyFont(size: 12, weight: .medium)
                .foregroundStyle(tint.color ?? Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 29)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : LauncherPalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.75) : LauncherPalette.separator,
                            lineWidth: isSelected ? 1.2 : 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func tintButton(_ choice: KeepAwakeIconTint) -> some View {
        let isSelected = choice == tint
        return Button {
            tint = choice
        } label: {
            ZStack {
                if let color = choice.color {
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.2)
                        .frame(width: 12, height: 12)
                    Image(systemName: "line.diagonal")
                        .commandlyFont(size: 8, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : Color.clear,
                        lineWidth: 1.1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension KeepAwakeIconTint {
    /// Commandly tint for the active menu bar glyph, `nil` when the glyph stays untinted.
    var color: Color? {
        switch self {
        case .orange: return CommandlyTint.orange.color
        case .green: return CommandlyTint.green.color
        case .blue: return CommandlyTint.blue.color
        case .purple: return CommandlyTint.purple.color
        case .pink: return CommandlyTint.pink.color
        case .untinted: return nil
        }
    }
}
