import Infrastructure
import SwiftUI

struct ShelfActionMenu: View {
    @Bindable var model: ShelfBoardModel
    var prepare: () -> Void = {}
    var onRename: () -> Void = {}
    var onTrash: () -> Void = {}
    var allowsRename = false
    var allowsTrash = false

    var body: some View {
        Group {
            Button("Open", systemImage: "arrow.up.forward.app") {
                preparedTask { await $0.openSelected() }
            }

            Menu("Open With", systemImage: "app.badge") {
                if model.isLoadingActionOptions, model.openWithOptions.isEmpty {
                    Text("Loading applications…")
                } else if model.openWithOptions.isEmpty {
                    Text("No compatible applications")
                } else {
                    ForEach(model.openWithOptions) { option in
                        Button(option.title) {
                            preparedTask { model in
                                await model.openSelected(withApplication: option.id)
                            }
                        }
                    }
                }
            }

            Button("Show in Finder", systemImage: "finder") {
                preparedTask { await $0.revealSelected() }
            }

            Button("Quick Look", systemImage: "eye") {
                prepare()
                model.previewSelected()
            }

            Divider()

            ForEach(NativeShareDestination.allCases, id: \.rawValue) { destination in
                Button(destination.shelfTitle, systemImage: destination.shelfSystemImage) {
                    preparedTask { await $0.share(to: destination) }
                }
                .disabled(model.canShare(to: destination) == false)
            }

            Menu("More Sharing", systemImage: "square.and.arrow.up") {
                if model.isLoadingActionOptions, model.sharingOptions.isEmpty {
                    Text("Loading sharing services…")
                } else if model.sharingOptions.isEmpty {
                    Text("No additional services")
                } else {
                    ForEach(model.sharingOptions) { option in
                        Button(option.title) {
                            preparedTask { model in
                                await model.shareSelected(withService: option.id)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Add From Clipboard", systemImage: "clipboard.badge.plus") {
                preparedTask { await $0.addFromClipboard() }
            }

            Button("Copy Items", systemImage: "doc.on.clipboard") {
                preparedTask { await $0.copyItemsToClipboard() }
            }

            Button("Copy Paths", systemImage: "text.document") {
                preparedTask { await $0.copyPathsToClipboard() }
            }

            Button("Copy To…", systemImage: "folder.badge.plus") {
                preparedTask { await $0.copySelectedToChosenFolder() }
            }

            Button("Move To…", systemImage: "folder") {
                preparedTask { await $0.moveSelectedToChosenFolder() }
            }

            Button("Duplicate", systemImage: "plus.square.on.square") {
                preparedTask { await $0.duplicateSelected() }
            }

            if allowsRename {
                Button("Rename…", systemImage: "pencil") {
                    prepare()
                    onRename()
                }
                .disabled(model.actionItems.count != 1)
            }

            Divider()

            Button("Remove From Shelf", systemImage: "minus.circle") {
                prepare()
                model.removeSelectedFromShelf()
            }

            Button("Clear Shelf", systemImage: "xmark.square") {
                model.clear()
            }

            if allowsTrash {
                Button("Move to Trash…", systemImage: "trash", role: .destructive) {
                    prepare()
                    onTrash()
                }
            }
        }
        .disabled(model.isPerformingAction)
        .onAppear {
            prepare()
            model.perform { model in
                async let openWith: Void = model.refreshOpenWithOptions()
                async let sharing: Void = model.refreshSharingOptions()
                _ = await (openWith, sharing)
            }
        }
    }

    private func preparedTask(
        _ operation: @escaping @MainActor (ShelfBoardModel) async -> Void
    ) {
        prepare()
        model.perform(operation)
    }
}
