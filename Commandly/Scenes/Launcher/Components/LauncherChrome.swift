import SwiftUI
import DesignSystem

struct LauncherSearchField: View {
    @Binding var query: String
    var onSubmit: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search apps and commands…", text: $query)
                .textFieldStyle(.plain)
                .commandlyFont(size: 16, weight: .medium)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Search apps and commands")

            if query.isEmpty == false {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .commandlyFont(size: 14, weight: .regular)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.searchVerticalPadding)
        .onAppear {
            isFocused = true
        }
    }
}

struct LauncherSectionHeader: View {
    let title: String
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Text(title.uppercased())
            .commandlyFont(size: 10, weight: .semibold)
            .foregroundStyle(.tertiary)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, density.spacing(.md))
            .padding(.top, density.sectionHeaderTopPadding)
            .padding(.bottom, density.spacing(.xxs))
            .accessibilityAddTraits(.isHeader)
    }
}

struct LauncherResultRow: View {
    let item: LauncherItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Button(action: action) {
            HStack(spacing: density.spacing(.sm)) {
                launcherIcon(
                    systemName: item.systemImage,
                    emphasized: isSelected,
                    size: density.iconSize
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .commandlyFont(size: 13, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .commandlyFont(size: 11, weight: .regular)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: density.spacing(.xs))

                Text(item.badge.title)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, density.rowHorizontalPadding)
            .padding(.vertical, density.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(isSelected ? BrandPalette.accent.opacity(0.22) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, density.spacing(.xs))
        .accessibilityLabel("\(item.title), \(item.badge.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct LauncherFooterBar: View {
    let primaryActionTitle: String
    var onPrimaryAction: () -> Void
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            Image(systemName: "command")
                .commandlyFont(size: 12, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: density.iconSize - 6, height: density.iconSize - 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )
                .accessibilityHidden(true)

            Text("Commandly")
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)

            Spacer(minLength: density.spacing(.sm))

            LauncherFooterActionButton(
                title: primaryActionTitle,
                keys: ["↩"],
                action: onPrimaryAction
            )

            footerDivider

            LauncherFooterActionButton(
                title: "Settings",
                keys: ["⌘", ","],
                action: onOpenSettings
            )

            footerDivider

            LauncherFooterActionButton(
                title: "Close",
                keys: ["Esc"],
                action: onClose
            )
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 14)
    }
}

private struct LauncherFooterActionButton: View {
    let title: String
    let keys: [String]
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)

                HStack(spacing: 3) {
                    ForEach(keys, id: \.self) { key in
                        Text(key)
                            .commandlyFont(size: 10, weight: .semibold, design: .rounded)
                            .foregroundStyle(isHovered ? BrandPalette.accentSoft : Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(
                                        isHovered
                                            ? BrandPalette.accent.opacity(0.22)
                                            : Color.primary.opacity(0.08)
                                    )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        BrandPalette.accent.opacity(isHovered ? 0.35 : 0),
                                        lineWidth: 1
                                    )
                            }
                            .shadow(
                                color: BrandPalette.accent.opacity(isHovered ? 0.28 : 0),
                                radius: isHovered ? 6 : 0,
                                y: isHovered ? 1 : 0
                            )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? BrandPalette.accent.opacity(0.12) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        BrandPalette.accent.opacity(isHovered ? 0.22 : 0),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.03 : 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title)
    }
}

func launcherIcon(systemName: String, emphasized: Bool, size: CGFloat = 28) -> some View {
    Image(systemName: systemName)
        .commandlyFont(size: size * 0.46, weight: .semibold)
        .foregroundStyle(emphasized ? Color.white : BrandPalette.accentSoft)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    emphasized
                        ? BrandPalette.accent
                        : BrandPalette.accent.opacity(0.16)
                )
        )
        .accessibilityHidden(true)
}
