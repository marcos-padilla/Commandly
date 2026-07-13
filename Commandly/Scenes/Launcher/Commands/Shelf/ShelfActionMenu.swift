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
                preparedTask { await model.openSelected() }
            }

            Menu("Open With", systemImage: "app.badge") {
                if model.isLoadingActionOptions, model.openWithOptions.isEmpty {
                    Text("Loading applications…")
                } else if model.openWithOptions.isEmpty {
                    Text("No compatible applications")
                } else {
                    ForEach(model.openWithOptions) { option in
                        Button(option.title) {
                            preparedTask {
                                await model.openSelected(withApplication: option.id)
                            }
                        }
                    }
                }
            }

            Button("Show in Finder", systemImage: "finder") {
                preparedTask { await model.revealSelected() }
            }

            Button("Quick Look", systemImage: "eye") {
                prepare()
                model.previewSelected()
            }

            Divider()

            ForEach(NativeShareDestination.allCases, id: \.rawValue) { destination in
                Button(destination.shelfTitle, systemImage: destination.shelfSystemImage) {
                    preparedTask { await model.share(to: destination) }
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
                            preparedTask {
                                await model.shareSelected(withService: option.id)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Add From Clipboard", systemImage: "clipboard.badge.plus") {
                preparedTask { await model.addFromClipboard() }
            }

            Button("Copy Items", systemImage: "doc.on.clipboard") {
                preparedTask { await model.copyItemsToClipboard() }
            }

            Button("Copy Paths", systemImage: "text.document") {
                preparedTask { await model.copyPathsToClipboard() }
            }

            Button("Copy To…", systemImage: "folder.badge.plus") {
                preparedTask { await model.copySelectedToChosenFolder() }
            }

            Button("Move To…", systemImage: "folder") {
                preparedTask { await model.moveSelectedToChosenFolder() }
            }

            Button("Duplicate", systemImage: "plus.square.on.square") {
                preparedTask { await model.duplicateSelected() }
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
        .onAppear {
            prepare()
            Task {
                async let openWith: Void = model.refreshOpenWithOptions()
                async let sharing: Void = model.refreshSharingOptions()
                _ = await (openWith, sharing)
            }
        }
    }

    private func preparedTask(_ operation: @escaping @MainActor () async -> Void) {
        prepare()
        Task {
            await operation()
        }
    }
}
