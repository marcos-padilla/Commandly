import SwiftUI
import DesignSystem
import CommandKit

/// Searchable application actions panel (original Commandly chrome).
struct ApplicationActionsPanel: View {
    let title: String
    let actions: [LauncherApplicationAction]
    @Binding var query: String
    var onSelect: (CommandActionID) -> Void
    var onDismiss: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, density.spacing(.md))
                .padding(.top, density.spacing(.sm))
                .padding(.bottom, density.spacing(.xs))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0, actions[index - 1].section != action.section {
                            Divider()
                                .opacity(0.35)
                                .padding(.vertical, 4)
                                .padding(.horizontal, density.spacing(.sm))
                        }
                        ApplicationActionRow(action: action) {
                            onSelect(action.id)
                        }
                    }
                }
                .padding(.horizontal, density.spacing(.xs))
                .padding(.bottom, density.spacing(.xs))
            }
            .frame(maxHeight: 280)

            Divider().opacity(0.35)

            HStack(spacing: density.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.tertiary)
                TextField("Search for actions…", text: $query)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 12, weight: .medium)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = actions.first {
                            onSelect(first.id)
                        }
                    }
            }
            .padding(.horizontal, density.spacing(.md))
            .padding(.vertical, density.spacing(.sm))
        }
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(title)")
    }
}

private struct ApplicationActionRow: View {
    let action: LauncherApplicationAction
    let onSelect: () -> Void
    @State private var isHovered = false
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: action.systemImage)
                    .commandlyFont(size: 12, weight: .semibold)
                    .foregroundStyle(action.isDestructive ? Color.orange : Color.primary.opacity(0.85))
                    .frame(width: 18, alignment: .center)

                Text(action.title)
                    .commandlyFont(size: 12, weight: .medium)
                    .foregroundStyle(action.isDestructive ? Color.orange : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let keys = action.keyHint?.symbols {
                    HStack(spacing: 3) {
                        ForEach(keys, id: \.self) { key in
                            Text(key)
                                .commandlyFont(size: 10, weight: .semibold, design: .rounded)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(action.title)
    }
}
