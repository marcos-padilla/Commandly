import DesignSystem
import SwiftUI

struct ShelfCompactContentView: View {
    @Bindable var model: ShelfBoardModel
    @Bindable var interaction: ShelfBoardInteractionState

    var body: some View {
        Group {
            if model.items.isEmpty {
                emptyContent
            } else {
                stagedContent
            }
        }
        .padding(.top, 30)
        .padding(.horizontal, Spacing.md.rawValue)
        .padding(.bottom, Spacing.md.rawValue)
    }

    private var emptyContent: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: interaction.isBoardDropTargeted ? "plus.circle.fill" : "tray.and.arrow.down")
                .commandlyFont(size: 24, weight: .semibold)
                .foregroundStyle(
                    interaction.isBoardDropTargeted
                        ? BrandPalette.accent
                        : Color.primary.opacity(0.42)
                )

            Text(dropPrompt)
                .commandlyFont(size: 13, weight: .medium)
                .foregroundStyle(.primary.opacity(interaction.isBoardDropTargeted ? 0.86 : 0.48))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dropPrompt)
    }

    private var stagedContent: some View {
        VStack(spacing: Spacing.sm.rawValue) {
            ZStack {
                ForEach(Array(model.items.suffix(4).enumerated()), id: \.element.id) { index, item in
                    ShelfCompactItemArtwork(item: item)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: offset(for: index).width, y: offset(for: index).height)
                        .zIndex(Double(index))
                        .draggable(containerItemID: item.id)
                }
            }
            .frame(width: 96, height: 86)
            .contentShape(Rectangle())
            .contextMenu {
                ShelfActionMenu(model: model)
            }

            Button {
                model.isShowingDetails = true
            } label: {
                HStack(spacing: Spacing.xxs.rawValue) {
                    Text(
                        interaction.isBoardDropTargeted
                            ? dropPrompt
                            : model.itemCountDescription
                    )
                    Image(systemName: interaction.isBoardDropTargeted ? "plus" : "chevron.right")
                        .commandlyFont(size: 9, weight: .bold)
                }
                .commandlyFont(size: 12, weight: .semibold)
                .foregroundStyle(.primary.opacity(0.84))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.11), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows Shelf item details and actions")
        }
        .dragContainer(for: ShelfItem.self) { ids in
            model.dragPayload(for: ids)
        }
        .dragContainerSelection(model.items.map(\.id))
        .dragConfiguration(ShelfDragConfiguration.value)
        .onDragSessionUpdated(handleDragSession)
    }

    private var dropPrompt: String {
        guard interaction.isBoardDropTargeted else { return "Drop files or folders here" }
        return "Release to add \(interaction.incomingItemDescription)"
    }

    private func rotation(for index: Int) -> Double {
        [-7, 5, -3, 2][index % 4]
    }

    private func offset(for index: Int) -> CGSize {
        let offsets = [
            CGSize(width: -8, height: 3),
            CGSize(width: 6, height: -4),
            CGSize(width: -2, height: 1),
            CGSize(width: 3, height: 0)
        ]
        return offsets[index % offsets.count]
    }

    private func handleDragSession(_ session: DragSession) {
        switch session.phase {
        case .initial, .active:
            interaction.beginShelfItemDrag()
        case .ended(let operation):
            let ids = session.draggedItemIDs(for: ShelfItem.ID.self)
            interaction.endShelfItemDrag()
            model.completeDragOut(
                itemIDs: ids,
                removesReferences: operation == .move || operation == .delete
            )
        case .dataTransferCompleted:
            interaction.endShelfItemDrag()
        @unknown default:
            interaction.endShelfItemDrag()
        }
    }
}

private struct ShelfCompactItemArtwork: View {
    let item: ShelfItem

    var body: some View {
        QuickLookSnapshotPreview(url: item.url, modificationDate: nil)
            .frame(width: 72, height: 72)
            .padding(5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            }
            .opacity(item.isAvailable ? 1 : 0.46)
            .accessibilityLabel(item.displayName)
    }
}

enum ShelfDragConfiguration {
    static let value = DragConfiguration(
        operationsWithinApp: .init(allowCopy: true, allowMove: false, allowDelete: false),
        operationsOutsideApp: .init(allowCopy: true, allowMove: false, allowDelete: false)
    )
}
