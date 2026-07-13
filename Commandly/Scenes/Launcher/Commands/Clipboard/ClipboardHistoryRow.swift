import DesignSystem
import SwiftUI

/// Sidebar row with hover Copy control. Copy sits outside the selection control
/// so clicking it does not also trigger row selection.
struct ClipboardHistoryRow: View {
    let entry: ClipboardHistoryEntry
    let isSelected: Bool
    let density: CommandlyLayoutDensity
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        LauncherApplicationRow(
            isSelected: isSelected,
            onSelect: onSelect,
            onHoverChange: handleHover
        ) {
            HStack(spacing: density.spacing(.sm)) {
                LauncherGlyph(
                    systemName: artwork.symbolName,
                    tone: artwork.tone,
                    isSelected: isSelected,
                    size: density.iconSize
                )
                Text(entry.preview)
                    .commandlyFont(size: 12, weight: .medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } accessory: {
            if isHovered {
                ClipboardHistoryCopyButton(onCopy: onCopy)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.preview)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Copy", onCopy)
    }

    private var artwork: LauncherFileArtwork {
        switch entry.contentType {
        case .text:
            return .text
        case .image:
            return .image
        case .fileURL:
            guard let url = entry.fileURLs.first else { return .generic }
            return LauncherFileArtwork(fileURL: url)
        }
    }

    private func handleHover(_ hovering: Bool) {
        isHovered = hovering
        onHoverChange(hovering)
    }
}

private struct ClipboardHistoryCopyButton: View {
    let onCopy: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var didSucceed = false
    @State private var successToken = 0

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: didSucceed ? "checkmark" : "doc.on.doc")
                    .commandlyFont(size: 10, weight: .semibold)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: didSucceed)

                Text(didSucceed ? "Copied" : "Copy")
                    .commandlyFont(size: 11, weight: .semibold)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        BrandPalette.accent.opacity(isHovered || didSucceed ? 0.28 : 0),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isPressed ? 0.96 : (isHovered || didSucceed ? 1.04 : 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(CopySuccessFeedback.succeedSpring, value: didSucceed)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task(id: successToken) {
            await CopySuccessFeedback.runMorph(token: successToken, didSucceed: $didSucceed)
        }
        .accessibilityLabel(didSucceed ? "Copied" : "Copy")
    }

    private var labelColor: Color {
        if didSucceed { return BrandPalette.accentSoft }
        return isHovered ? Color.primary : Color.secondary
    }

    private var fillColor: Color {
        if didSucceed { return BrandPalette.accent.opacity(0.22) }
        if isHovered { return BrandPalette.accent.opacity(0.14) }
        return Color.primary.opacity(0.08)
    }

    private func copy() {
        onCopy()
        successToken += 1
    }
}
