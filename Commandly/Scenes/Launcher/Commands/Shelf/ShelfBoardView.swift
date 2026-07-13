import DesignSystem
import SwiftUI

/// Floating Shelf board: glass material, close control, focus-aware handle, and empty-state copy.
struct ShelfBoardView: View {
    @Bindable var model: ShelfBoardModel
    @Bindable var interaction: ShelfBoardInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isCloseHovered = false
    @State private var showsDropPrompt = false

    private let restingHandleWidth: CGFloat = 34
    private let draggingHandleWidth: CGFloat = 52

    var body: some View {
        ZStack {
            boardBackground
            dropPrompt
            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
            }
        }
        .frame(
            width: LayoutConstants.shelfBoardSize,
            height: LayoutConstants.shelfBoardSize
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .task(id: model.entryMode) {
            await revealDropPrompt()
        }
    }

    private var boardBackground: some View {
        ZStack {
            LauncherVisualEffectBackground(
                material: .hudWindow,
                blendingMode: .behindWindow
            )

            // Soft body so the glass reads as a solid board without opaque color fill.
            Color.primary.opacity(0.06)

            RoundedRectangle(
                cornerRadius: LayoutConstants.shelfCornerRadius,
                style: .continuous
            )
            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        }
    }

    private var topChrome: some View {
        ZStack(alignment: .top) {
            if interaction.isFocused {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.28))
                    .frame(
                        width: interaction.isDragging ? draggingHandleWidth : restingHandleWidth,
                        height: 4
                    )
                    .padding(.top, 7)
                    .accessibilityHidden(true)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
            }

            HStack {
                closeButton
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(handleAnimation, value: interaction.isFocused)
        .animation(handleAnimation, value: interaction.isDragging)
    }

    private var dropPrompt: some View {
        Text("Drop files here")
            .commandlyFont(size: 13, weight: .medium)
            .foregroundStyle(.primary.opacity(0.48))
            .multilineTextAlignment(.center)
            .opacity(showsDropPrompt ? 1 : 0)
            .offset(y: showsDropPrompt ? 0 : 8)
            .scaleEffect(showsDropPrompt ? 1 : 0.96)
            .accessibilityHidden(showsDropPrompt == false)
            .accessibilityAddTraits(.isStaticText)
    }

    private var closeButton: some View {
        Button(action: model.close) {
            Image(systemName: "xmark")
                .commandlyFont(size: 12, weight: .bold)
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isCloseHovered ? 0.18 : 0.12))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovered = $0 }
        .accessibilityLabel("Close Shelf")
        .help("Close Shelf")
    }

    private var handleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: MotionDuration.instant.rawValue)
            : .spring(response: 0.32, dampingFraction: 0.82)
    }

    private var promptAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: MotionDuration.fast.rawValue)
            : .spring(response: 0.55, dampingFraction: 0.78)
    }

    private func revealDropPrompt() async {
        showsDropPrompt = false
        if reduceMotion {
            showsDropPrompt = true
            return
        }
        try? await Task.sleep(for: .milliseconds(420))
        guard Task.isCancelled == false else { return }
        withAnimation(promptAnimation) {
            showsDropPrompt = true
        }
    }
}

#Preview {
    let interaction = ShelfBoardInteractionState()
    return ShelfBoardView(
        model: ShelfBoardModel(entryMode: .empty, onClose: {}),
        interaction: interaction
    )
    .padding(40)
    .background(Color.black.opacity(0.35))
}
