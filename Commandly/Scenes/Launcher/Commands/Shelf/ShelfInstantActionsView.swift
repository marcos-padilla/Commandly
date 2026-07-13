import DesignSystem
import Infrastructure
import SwiftUI

struct ShelfInstantActionsView: View {
    @Bindable var model: ShelfBoardModel
    @Bindable var interaction: ShelfBoardInteractionState

    var body: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            ForEach(NativeShareDestination.allCases, id: \.rawValue) { destination in
                actionButton(destination)
            }
        }
        .frame(height: LayoutConstants.shelfInstantActionsHeight)
        .padding(.horizontal, Spacing.xs.rawValue)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Direct Shelf actions")
    }

    private func actionButton(_ destination: NativeShareDestination) -> some View {
        let isTargeted = interaction.targetedAction == destination
        return Button {
            Task {
                await model.share(to: destination)
            }
        } label: {
            VStack(spacing: 2) {
                nativeIcon(for: destination, isTargeted: isTargeted)

                Text(destination.shelfTitle)
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.primary.opacity(0.72))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Drop files to share with \(destination.shelfTitle)")
        .accessibilityLabel(destination.shelfTitle)
        .accessibilityValue(isTargeted ? "Drop target active" : "")
        .accessibilityHint("Drop files here, or activate to share staged Shelf items")
        .dropDestination(for: URL.self) { urls, _ in
            guard interaction.isDraggingShelfItems == false else { return }
            Task {
                await model.share(urls, to: destination)
            }
            interaction.endDropSession()
        }
        .dropConfiguration { _ in
            DropConfiguration(operation: .copy)
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                interaction.beginDropSession(itemCount: session.itemsCount)
                interaction.updateActionDropTarget(destination, isTargeted: true)
            case .exiting, .ended, .dataTransferCompleted:
                interaction.updateActionDropTarget(destination, isTargeted: false)
            @unknown default:
                interaction.updateActionDropTarget(destination, isTargeted: false)
            }
        }
    }

    private func nativeIcon(
        for destination: NativeShareDestination,
        isTargeted: Bool
    ) -> some View {
        Group {
            if let nativeImage = destination.shelfNativeImage {
                Image(nsImage: nativeImage)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Image(systemName: destination.shelfSystemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary.opacity(0.84))
            }
        }
        .frame(width: 21, height: 21)
        .frame(width: 32, height: 32)
        .background(
            isTargeted ? BrandPalette.accent.opacity(0.2) : Color.primary.opacity(0.08),
            in: Circle()
        )
        .overlay {
            Circle()
                .strokeBorder(
                    isTargeted ? BrandPalette.accent : Color.primary.opacity(0.12),
                    lineWidth: isTargeted ? 2 : 1
                )
        }
        .shadow(
            color: isTargeted ? BrandPalette.accent.opacity(0.32) : .clear,
            radius: 6
        )
    }
}
