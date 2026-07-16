import AppKit
import DesignSystem
import SwiftUI

/// Floating Shelf board with native content staging and an integrated detail surface.
struct ShelfBoardView: View {
    @Bindable var model: ShelfBoardModel
    @Bindable var interaction: ShelfBoardInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isCloseHovered = false
    @State private var isDragHandleHovered = false
    @State private var hasRevealedInitialContent = false
    @State private var hasRevealedEmptyPrompt = false

    private let restingHandleWidth: CGFloat = 34
    private let hoveredHandleWidth: CGFloat = 42
    private let emptyPromptRevealDelay: Duration = .seconds(1)
    private let emptyPromptRevealDuration = 0.72

    var body: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            boardSurface

            if interaction.showsInstantActions {
                ShelfInstantActionsView(model: model, interaction: interaction)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: boardWidth)
        .windowResizeAnchor(resizeAnchor)
        .animation(surfaceAnimation, value: model.isShowingDetails)
        .animation(surfaceAnimation, value: interaction.showsInstantActions)
        .onDropSessionUpdated(handleRootDropSession)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(boardAccessibilityValue)
        .task(id: ObjectIdentifier(model)) {
            let revealClock = ContinuousClock()
            let emptyPromptDeadline = revealClock.now.advanced(by: emptyPromptRevealDelay)
            hasRevealedInitialContent = false
            hasRevealedEmptyPrompt = false
            await model.loadInitialContent()
            guard Task.isCancelled == false else { return }
            if reduceMotion {
                hasRevealedInitialContent = true
                hasRevealedEmptyPrompt = true
            } else {
                withAnimation(.easeOut(duration: MotionDuration.normal.rawValue)) {
                    hasRevealedInitialContent = true
                }

                guard model.items.isEmpty else {
                    hasRevealedEmptyPrompt = true
                    return
                }

                do {
                    try await revealClock.sleep(
                        until: emptyPromptDeadline,
                        tolerance: .milliseconds(60)
                    )
                } catch {
                    return
                }
                guard Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: emptyPromptRevealDuration)) {
                    hasRevealedEmptyPrompt = true
                }
            }
        }
        .onDisappear {
            model.tearDown()
            interaction.endDropSession()
        }
        .alert(
            "Shelf Action Failed",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        model.dismissError()
                    }
                }
            )
        ) {
            Button("OK") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "The action could not be completed.")
        }
    }

    private var boardSurface: some View {
        ZStack {
            boardBackground

            if model.isShowingDetails {
                ShelfDetailsView(model: model, interaction: interaction)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ShelfCompactContentView(
                    model: model,
                    interaction: interaction,
                    hasRevealedEmptyPrompt: hasRevealedEmptyPrompt
                )
                    .opacity(hasRevealedInitialContent ? 1 : 0)
                    .scaleEffect(hasRevealedInitialContent || reduceMotion ? 1 : 0.95)
                    .accessibilityHidden(hasRevealedInitialContent == false)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
            }
        }
        .frame(width: boardWidth, height: boardHeight)
        .contentShape(
            RoundedRectangle(
                cornerRadius: LayoutConstants.shelfCornerRadius,
                style: .continuous
            )
        )
        .gesture(
            WindowDragGesture(),
            isEnabled: interaction.allowsWindowDragging
        )
        .allowsWindowActivationEvents()
        .dropDestination(for: URL.self) { urls, _ in
            guard interaction.isDraggingShelfItems == false else { return }
            _ = model.stage(urls)
            interaction.endDropSession()
        }
        .dropConfiguration { _ in
            DropConfiguration(operation: .copy)
        }
        .onDropSessionUpdated(handleBoardDropSession)
    }

    private var boardBackground: some View {
        ShelfPersistentGlassBackground()
        .clipShape(
            RoundedRectangle(
                cornerRadius: LayoutConstants.shelfCornerRadius,
                style: .continuous
            )
        )
        .glassEffect(
            .clear,
            in: .rect(cornerRadius: LayoutConstants.shelfCornerRadius)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: LayoutConstants.shelfCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                interaction.isBoardDropTargeted
                    ? BrandPalette.accent
                    : Color.primary.opacity(0.1),
                lineWidth: interaction.isBoardDropTargeted ? 2.5 : 0.75
            )
        }
        .shadow(
            color: interaction.isBoardDropTargeted
                ? BrandPalette.accent.opacity(0.34)
                : Color.black.opacity(0.16),
            radius: interaction.isBoardDropTargeted ? 12 : 18,
            y: interaction.isBoardDropTargeted ? 0 : 8
        )
    }

    private var topChrome: some View {
        ZStack(alignment: .top) {
            HStack {
                closeButton
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            windowDragHandle
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(handleAnimation, value: interaction.isFocused)
        .animation(handleAnimation, value: isDragHandleHovered)
    }

    private var windowDragHandle: some View {
        ShelfWindowDragHandle()
            .frame(width: 72, height: 26)
            .overlay {
                if interaction.isFocused {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.28))
                        .frame(
                            width: isDragHandleHovered ? hoveredHandleWidth : restingHandleWidth,
                            height: 4
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                }
            }
            .padding(.top, 2)
            .onHover { isDragHandleHovered = $0 }
            .allowsWindowActivationEvents()
            .accessibilityHidden(true)
            .help("Drag to move Shelf")
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

    private var boardWidth: CGFloat {
        model.isShowingDetails
            ? LayoutConstants.shelfDetailWidth
            : LayoutConstants.shelfBoardSize
    }

    private var boardHeight: CGFloat {
        model.isShowingDetails
            ? LayoutConstants.shelfDetailHeight
            : LayoutConstants.shelfBoardSize
    }

    private var resizeAnchor: UnitPoint {
        switch model.configuration.preferredCorner {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft: return .bottomLeading
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        }
    }

    private var boardAccessibilityValue: String {
        guard interaction.isBoardDropTargeted else { return model.accessibilityValue }
        return "\(model.accessibilityValue). Drop target active for \(interaction.incomingItemDescription)."
    }

    private var handleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: MotionDuration.instant.rawValue)
            : .spring(response: 0.32, dampingFraction: 0.82)
    }

    private var surfaceAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: MotionDuration.instant.rawValue)
            : .spring(response: 0.36, dampingFraction: 0.86)
    }

    private func handleRootDropSession(_ session: DropSession) {
        switch session.phase {
        case .entering, .active:
            interaction.beginDropSession(itemCount: session.itemsCount)
        case .exiting, .ended, .dataTransferCompleted:
            interaction.endDropSession()
        @unknown default:
            interaction.endDropSession()
        }
    }

    private func handleBoardDropSession(_ session: DropSession) {
        switch session.phase {
        case .entering, .active:
            interaction.beginDropSession(itemCount: session.itemsCount)
            interaction.updateBoardDropTarget(isTargeted: true)
        case .exiting, .ended, .dataTransferCompleted:
            interaction.updateBoardDropTarget(isTargeted: false)
        @unknown default:
            interaction.updateBoardDropTarget(isTargeted: false)
        }
    }
}

/// Keeps Shelf's behind-window material optically alive while another application has focus.
///
/// Shelf intentionally remains visible across application changes, so following the key-window
/// state makes its material turn into a comparatively solid inactive fill. The active material
/// state preserves desktop sampling while macOS still owns contrast and Reduce Transparency.
private struct ShelfPersistentGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}
