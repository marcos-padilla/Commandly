import DesignSystem
import SwiftUI

struct ShelfDetailsView: View {
    @Bindable var model: ShelfBoardModel
    @Bindable var interaction: ShelfBoardInteractionState

    @State private var renameTarget: ShelfItem?
    @State private var renameText = ""
    @State private var confirmsTrash = false

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 126), spacing: Spacing.xs.rawValue)
    ]

    var body: some View {
        VStack(spacing: Spacing.sm.rawValue) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.xs.rawValue) {
                    ForEach(model.items) { item in
                        itemCell(item)
                            .draggable(containerItemID: item.id)
                    }
                }
                .padding(.horizontal, Spacing.md.rawValue)
                .padding(.bottom, Spacing.sm.rawValue)
            }
            .scrollIndicators(.automatic)

            footer
        }
        .padding(.top, 10)
        .padding(.bottom, Spacing.sm.rawValue)
        .dragContainer(for: ShelfItem.self) { ids in
            model.dragPayload(for: ids)
        }
        .dragContainerSelection(Array(model.selectedItemIDs))
        .dragConfiguration(ShelfDragConfiguration.value)
        .onDragSessionUpdated(handleDragSession)
        .alert(
            "Rename Item",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { isPresented in
                    if isPresented == false {
                        renameTarget = nil
                    }
                }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Rename") {
                guard let target = renameTarget else { return }
                let proposedName = renameText
                renameTarget = nil
                Task {
                    await model.rename(target.id, to: proposedName)
                }
            }
        } message: {
            Text("Rename the file or folder on disk. The Shelf reference updates automatically.")
        }
        .alert("Move to Trash?", isPresented: $confirmsTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task {
                    await model.moveSelectedToTrash()
                }
            }
        } message: {
            Text("This moves the selected files or folders on disk to the Trash.")
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            Button {
                model.isShowingDetails = false
            } label: {
                Image(systemName: "chevron.left")
                    .commandlyFont(size: 13, weight: .bold)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.11), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to compact Shelf")

            VStack(alignment: .leading, spacing: 1) {
                Text(model.itemCountDescription)
                    .commandlyFont(size: 14, weight: .semibold)
                Text(model.selectionSummary)
                    .commandlyFont(size: 10, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(model.selectedItemIDs.count == model.items.count ? "Clear Selection" : "Select All") {
                if model.selectedItemIDs.count == model.items.count {
                    model.clearSelection()
                } else {
                    model.selectAll()
                }
            }
            .buttonStyle(.plain)
            .commandlyFont(size: 10, weight: .medium)
            .foregroundStyle(BrandPalette.accent)

            Menu {
                ShelfActionMenu(
                    model: model,
                    onRename: beginRename,
                    onTrash: { confirmsTrash = true },
                    allowsRename: true,
                    allowsTrash: true
                )
            } label: {
                Image(systemName: "ellipsis")
                    .commandlyFont(size: 14, weight: .bold)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.11), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Shelf actions")
        }
        .padding(.leading, 48)
        .padding(.trailing, Spacing.md.rawValue)
    }

    private var footer: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            if model.isPerformingAction {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Shelf action in progress")
            }

            Text(model.statusMessage ?? "Drag selected items out, or use the actions menu.")
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    await model.addFromClipboard()
                }
            } label: {
                Image(systemName: "clipboard")
            }
            .buttonStyle(.plain)
            .help("Add files from Clipboard")
            .accessibilityLabel("Add files from Clipboard")
        }
        .padding(.horizontal, Spacing.md.rawValue)
        .accessibilityElement(children: .contain)
    }

    private func itemCell(_ item: ShelfItem) -> some View {
        let isSelected = model.selectedItemIDs.contains(item.id)
        return Button {
            model.toggleSelection(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    QuickLookSnapshotPreview(url: item.url, modificationDate: nil)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .padding(5)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .commandlyFont(size: 14, weight: .semibold)
                            .foregroundStyle(Color.white, BrandPalette.accent)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }

                Text(item.displayName)
                    .commandlyFont(size: 10, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metadataText(for: item))
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? BrandPalette.accent.opacity(0.86) : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? BrandPalette.accentSoft : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .opacity(item.isAvailable ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(isSelected ? "Selected" : metadataText(for: item))
        .accessibilityHint("Selects this item. Drag to another application to move or copy it.")
        .contextMenu {
            ShelfActionMenu(
                model: model,
                prepare: { model.selectOnly(item.id) },
                onRename: { beginRename(item) },
                onTrash: {
                    model.selectOnly(item.id)
                    confirmsTrash = true
                },
                allowsRename: true,
                allowsTrash: true
            )
        }
    }

    private func metadataText(for item: ShelfItem) -> String {
        if item.isAvailable == false {
            return "Unavailable"
        }
        if item.isDirectory {
            return "Folder"
        }
        guard let byteCount = item.byteCount else { return "File" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func beginRename() {
        guard let item = model.actionItems.first, model.actionItems.count == 1 else { return }
        beginRename(item)
    }

    private func beginRename(_ item: ShelfItem) {
        model.selectOnly(item.id)
        renameText = item.displayName
        renameTarget = item
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
