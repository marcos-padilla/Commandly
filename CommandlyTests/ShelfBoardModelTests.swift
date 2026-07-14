import AppKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct ShelfBoardModelTests {
    @Test @MainActor
    func describesHomogeneousShelfItemsByTheirResourceType() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let firstImage = fixture.root.appendingPathComponent("First.jpg")
        let secondImage = fixture.root.appendingPathComponent("Second.png")
        let firstPDF = fixture.root.appendingPathComponent("First.pdf")
        let secondPDF = fixture.root.appendingPathComponent("Second.pdf")
        let firstDocument = fixture.root.appendingPathComponent("First.docx")
        let secondDocument = fixture.root.appendingPathComponent("Second.docx")
        let secondFolder = fixture.root.appendingPathComponent("Archive", isDirectory: true)
        let metadata = [
            shelfMetadata(url: firstImage, type: "public.jpeg"),
            shelfMetadata(url: secondImage, type: "public.png"),
            shelfMetadata(url: firstPDF, type: "com.adobe.pdf"),
            shelfMetadata(url: secondPDF, type: "com.adobe.pdf"),
            shelfMetadata(
                url: firstDocument,
                type: "org.openxmlformats.wordprocessingml.document"
            ),
            shelfMetadata(
                url: secondDocument,
                type: "org.openxmlformats.wordprocessingml.document"
            ),
            shelfMetadata(url: fixture.folder, isDirectory: true, type: "public.folder"),
            shelfMetadata(url: secondFolder, isDirectory: true, type: "public.folder")
        ]

        let imageModel = makeShelfModel(metadata: metadata)
        #expect(imageModel.stage([firstImage]) == 1)
        await yieldUntil { imageModel.items.allSatisfy { $0.contentTypeIdentifier != nil } }
        #expect(imageModel.itemCountDescription == "1 image")
        #expect(imageModel.stage([secondImage]) == 1)
        await yieldUntil {
            imageModel.items.count == 2
                && imageModel.items.allSatisfy { $0.contentTypeIdentifier != nil }
        }
        #expect(imageModel.itemCountDescription == "2 images")

        let pdfModel = makeShelfModel(metadata: metadata)
        #expect(pdfModel.stage([firstPDF, secondPDF]) == 2)
        await yieldUntil { pdfModel.items.allSatisfy { $0.contentTypeIdentifier != nil } }
        #expect(pdfModel.itemCountDescription == "2 PDFs")

        let documentModel = makeShelfModel(metadata: metadata)
        #expect(documentModel.stage([firstDocument, secondDocument]) == 2)
        await yieldUntil { documentModel.items.allSatisfy { $0.contentTypeIdentifier != nil } }
        #expect(documentModel.itemCountDescription == "2 documents")

        let folderModel = makeShelfModel(metadata: metadata)
        #expect(folderModel.stage([fixture.folder]) == 1)
        await yieldUntil { folderModel.items.allSatisfy(\.isDirectory) }
        #expect(folderModel.itemCountDescription == "1 folder")
        #expect(folderModel.stage([secondFolder]) == 1)
        await yieldUntil {
            folderModel.items.count == 2 && folderModel.items.allSatisfy(\.isDirectory)
        }
        #expect(folderModel.itemCountDescription == "2 folders")
    }

    @Test @MainActor
    func describesHeterogeneousShelfContentsAsItems() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let image = fixture.root.appendingPathComponent("Preview.jpg")
        let pdf = fixture.root.appendingPathComponent("Guide.pdf")
        let metadata = [
            shelfMetadata(url: image, type: "public.jpeg"),
            shelfMetadata(url: pdf, type: "com.adobe.pdf"),
            shelfMetadata(url: fixture.folder, isDirectory: true, type: "public.folder")
        ]

        let mixedFiles = makeShelfModel(metadata: metadata)
        #expect(mixedFiles.stage([image, pdf]) == 2)
        await yieldUntil { mixedFiles.items.allSatisfy { $0.contentTypeIdentifier != nil } }
        #expect(mixedFiles.itemCountDescription == "2 items")

        let fileAndFolder = makeShelfModel(metadata: metadata)
        #expect(fileAndFolder.stage([image, fixture.folder]) == 2)
        await yieldUntil {
            fileAndFolder.items.allSatisfy { $0.contentTypeIdentifier != nil }
        }
        #expect(fileAndFolder.itemCountDescription == "2 items")
    }

    @Test @MainActor
    func dropSessionRetainsKnownCountAndUsesGenericUnknownDescription() {
        let interaction = ShelfBoardInteractionState()

        #expect(interaction.incomingItemCount == 0)
        #expect(interaction.incomingItemDescription == "files and folders")

        interaction.beginDropSession(itemCount: 3)
        #expect(interaction.incomingItemCount == 3)
        #expect(interaction.incomingItemDescription == "3 items")

        interaction.beginDropSession(itemCount: 0)
        #expect(interaction.incomingItemCount == 3)
        #expect(interaction.incomingItemDescription == "3 items")

        interaction.endDropSession()
        #expect(interaction.incomingItemCount == 0)
        #expect(interaction.incomingItemDescription == "files and folders")

        interaction.beginDropSession(itemCount: 0)
        #expect(interaction.incomingItemCount == 0)
        #expect(interaction.incomingItemDescription == "files and folders")

        interaction.beginDropSession(itemCount: 1)
        #expect(interaction.incomingItemDescription == "1 item")
    }

    @Test @MainActor
    func outgoingShelfItemDragCannotActivateIncomingDropChrome() {
        let interaction = ShelfBoardInteractionState()

        #expect(interaction.allowsWindowDragging)
        interaction.beginShelfItemDrag()
        interaction.beginDropSession(itemCount: 2)
        interaction.updateBoardDropTarget(isTargeted: true)
        interaction.updateActionDropTarget(.airDrop, isTargeted: true)

        #expect(interaction.isDraggingShelfItems)
        #expect(interaction.allowsWindowDragging == false)
        #expect(interaction.showsInstantActions == false)
        #expect(interaction.isBoardDropTargeted == false)
        #expect(interaction.targetedAction == nil)
        #expect(interaction.incomingItemCount == 0)

        interaction.endShelfItemDrag()
        interaction.beginDropSession(itemCount: 2)
        interaction.updateBoardDropTarget(isTargeted: true)

        #expect(interaction.isDraggingShelfItems == false)
        #expect(interaction.allowsWindowDragging)
        #expect(interaction.showsInstantActions)
        #expect(interaction.isBoardDropTargeted)
        #expect(interaction.incomingItemCount == 2)
    }

    @Test @MainActor
    func stagesFilesAndFoldersDeduplicatesAndLoadsMetadata() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let webURL = try #require(URL(string: "https://example.com/not-a-file"))
        let metadata = [
            FileResourceMetadata(
                url: fixture.file,
                displayName: "Project Notes.txt",
                isDirectory: false,
                byteCount: 12,
                contentTypeIdentifier: "public.plain-text"
            ),
            FileResourceMetadata(
                url: fixture.folder,
                displayName: "Reference Folder",
                isDirectory: true,
                contentTypeIdentifier: "public.folder"
            )
        ]
        let model = makeShelfModel(metadata: metadata)

        let accepted = model.stage([
            fixture.file,
            fixture.folder,
            fixture.file,
            webURL
        ])

        #expect(accepted == 2)
        #expect(model.items.map(\.url) == [fixture.file, fixture.folder])
        #expect(model.accessibilityValue == "2 items")
        await yieldUntil {
            model.items.allSatisfy { $0.contentTypeIdentifier != nil }
        }
        let file = try #require(model.items.first { $0.url == fixture.file })
        let folder = try #require(model.items.first { $0.url == fixture.folder })
        #expect(file.displayName == "Project Notes.txt")
        #expect(file.byteCount == 12)
        #expect(file.isDirectory == false)
        #expect(folder.displayName == "Reference Folder")
        #expect(folder.isDirectory)

        #expect(model.stage([fixture.file, webURL]) == 0)
        #expect(model.items.count == 2)
    }

    @Test @MainActor
    func selectionAndDragCompletionOnlyRemoveShelfReferencesForMoveOrDelete() throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let model = makeShelfModel()
        #expect(model.stage([fixture.file, fixture.secondFile, fixture.folder]) == 3)
        let firstID = try #require(model.items.first?.id)
        let lastID = try #require(model.items.last?.id)

        model.toggleSelection(lastID)
        model.toggleSelection(firstID)
        #expect(model.actionURLs == [fixture.file, fixture.folder])
        #expect(model.selectionSummary == "2 items selected")
        #expect(model.dragPayload(for: [lastID, firstID]).map(\.url) == [
            fixture.file,
            fixture.folder
        ])

        model.completeDragOut(itemIDs: [firstID], removesReferences: false)
        #expect(model.items.count == 3)
        model.completeDragOut(itemIDs: [firstID], removesReferences: true)
        #expect(model.items.map(\.url) == [fixture.secondFile, fixture.folder])
        #expect(model.selectedItemIDs == [lastID])
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
    }

    @Test @MainActor
    func clipboardEntryModeSeedsOnceAndCopiesOnlyTheSelection() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let pasteboard = InMemoryPasteboard(initialFileURLs: [fixture.file, fixture.folder])
        let temporaryContentStore = InMemoryShelfTemporaryContentStore()
        let model = makeShelfModel(
            entryMode: .fromClipboard,
            pasteboard: pasteboard,
            temporaryContentStore: temporaryContentStore
        )

        await model.loadInitialContent()
        await model.loadInitialContent()
        #expect(model.items.map(\.url) == [fixture.file, fixture.folder])
        #expect(model.items.allSatisfy { $0.ownership == .externalReference })
        let storeSnapshot = await temporaryContentStore.snapshot()
        #expect(storeSnapshot.textValues.isEmpty)
        #expect(storeSnapshot.imageValues.isEmpty)

        let folderID = try #require(model.items.last?.id)
        model.selectOnly(folderID)
        await model.copyItemsToClipboard()
        #expect(pasteboard.currentFileURLs == [fixture.folder])
        #expect(model.statusMessage == "Item copied.")
    }

    @Test @MainActor
    func clipboardEntryModeMaterializesTextExactlyOnceAsTemporaryContent() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let text = "  Draft idea\nSecond line  "
        let materializedURL = fixture.root.appendingPathComponent("Clipboard Text.txt")
        let pasteboard = InMemoryPasteboard(initial: text)
        let temporaryContentStore = InMemoryShelfTemporaryContentStore(
            textFileURL: materializedURL
        )
        let model = makeShelfModel(
            entryMode: .fromClipboard,
            pasteboard: pasteboard,
            temporaryContentStore: temporaryContentStore
        )

        await model.loadInitialContent()
        await model.loadInitialContent()

        let item = try #require(model.items.first)
        #expect(model.items.count == 1)
        #expect(item.url == materializedURL)
        #expect(item.ownership == .shelfTemporary)
        #expect(item.kind == .document)
        let snapshot = await temporaryContentStore.snapshot()
        #expect(snapshot.textValues == [text])
        #expect(snapshot.imageValues.isEmpty)
    }

    @Test @MainActor
    func clipboardEntryModeMaterializesStandaloneImageWithItsOriginalBytes() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let image = PasteboardImageContent(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            typeIdentifier: "public.png"
        )
        let materializedURL = fixture.root.appendingPathComponent("Clipboard Image.png")
        let pasteboard = InMemoryPasteboard(initialImage: image)
        let temporaryContentStore = InMemoryShelfTemporaryContentStore(
            imageFileURL: materializedURL
        )
        let model = makeShelfModel(
            entryMode: .fromClipboard,
            pasteboard: pasteboard,
            temporaryContentStore: temporaryContentStore
        )

        await model.loadInitialContent()

        let item = try #require(model.items.first)
        #expect(model.items.count == 1)
        #expect(item.url == materializedURL)
        #expect(item.ownership == .shelfTemporary)
        #expect(item.kind == .image)
        let snapshot = await temporaryContentStore.snapshot()
        #expect(snapshot.imageValues == [image])
        #expect(snapshot.textValues.isEmpty)
    }

    @Test @MainActor
    func removingTemporaryClipboardContentAndTearingDownCleansOnlyBoardOwnedFiles() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let materializedURL = fixture.root.appendingPathComponent("Clipboard Text.txt")
        let temporaryContentStore = InMemoryShelfTemporaryContentStore(
            textFileURL: materializedURL
        )
        let model = makeShelfModel(
            entryMode: .fromClipboard,
            pasteboard: InMemoryPasteboard(initial: "Temporary note"),
            temporaryContentStore: temporaryContentStore
        )

        await model.loadInitialContent()
        #expect(model.stage([fixture.file, fixture.folder]) == 2)
        let temporaryItem = try #require(
            model.items.first { $0.ownership == .shelfTemporary }
        )

        model.remove(temporaryItem.id)
        let removalSnapshot = await yieldUntilStoreSnapshot(temporaryContentStore) {
            $0.discardedURLs == [materializedURL]
        }
        #expect(removalSnapshot.discardedURLs == [materializedURL])
        #expect(model.items.map(\.url) == [fixture.file, fixture.folder])
        #expect(model.items.allSatisfy { $0.ownership == .externalReference })
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
        #expect(FileManager.default.fileExists(atPath: fixture.folder.path))

        await model.addFromClipboard()
        #expect(model.items.contains { $0.ownership == .shelfTemporary })
        model.tearDown()
        model.tearDown()
        let teardownSnapshot = await yieldUntilStoreSnapshot(temporaryContentStore) {
            $0.discardAllCount == 1
        }
        #expect(teardownSnapshot.discardAllCount == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
        #expect(FileManager.default.fileExists(atPath: fixture.folder.path))
    }

    @Test @MainActor
    func localTemporaryContentStoresWriteExactDataRemainIsolatedAndCleanUp() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let firstIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let firstStore = LocalShelfTemporaryContentStore(
            temporaryDirectory: fixture.root,
            identifier: firstIdentifier
        )
        let secondStore = LocalShelfTemporaryContentStore(
            temporaryDirectory: fixture.root,
            identifier: secondIdentifier
        )
        let text = "Text with leading space, emoji 🫙, and newline\n"
        let image = PasteboardImageContent(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02]),
            typeIdentifier: "public.png"
        )

        let firstTextURL = try await firstStore.createTextFile(containing: text)
        let firstImageURL = try await firstStore.createImageFile(image)
        let secondTextURL = try await secondStore.createTextFile(containing: "Second board")
        let firstRoot = firstTextURL.deletingLastPathComponent()
        let secondRoot = secondTextURL.deletingLastPathComponent()

        #expect(firstRoot.lastPathComponent == "Shelf-\(firstIdentifier.uuidString)")
        #expect(secondRoot.lastPathComponent == "Shelf-\(secondIdentifier.uuidString)")
        #expect(firstRoot != secondRoot)
        #expect(firstTextURL.lastPathComponent == "Clipboard Text.txt")
        #expect(firstImageURL.lastPathComponent == "Clipboard Image.png")
        #expect(try Data(contentsOf: firstTextURL) == Data(text.utf8))
        #expect(try Data(contentsOf: firstImageURL) == image.data)
        let attributes = try FileManager.default.attributesOfItem(atPath: firstRoot.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o700)

        await firstStore.discard([firstTextURL])
        #expect(FileManager.default.fileExists(atPath: firstTextURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: firstImageURL.path))
        #expect(FileManager.default.fileExists(atPath: secondTextURL.path))

        await firstStore.discardAll()
        #expect(FileManager.default.fileExists(atPath: firstRoot.path) == false)
        #expect(FileManager.default.fileExists(atPath: secondTextURL.path))

        await secondStore.discardAll()
        #expect(FileManager.default.fileExists(atPath: secondRoot.path) == false)
    }

    @Test @MainActor
    func nativePasteboardReaderSupportsFilesFoldersImagesAndExactText() throws {
        let pasteboard = NSPasteboard(
            name: .init("CommandlyTests.ShelfPasteboard.\(UUID().uuidString)")
        )
        defer { pasteboard.clearContents() }

        let text = "  Clipboard note with intentional spacing\n"
        pasteboard.clearContents()
        #expect(pasteboard.setString(text, forType: .string))
        #expect(NativePasteboardContentReader.read(from: pasteboard) == .text(text))

        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        pasteboard.clearContents()
        #expect(pasteboard.setData(pngData, forType: .png))
        #expect(
            NativePasteboardContentReader.read(from: pasteboard)
                == .image(
                    PasteboardImageContent(
                        data: pngData,
                        typeIdentifier: "public.png"
                    )
                )
        )

        let tiffData = Data([0x49, 0x49, 0x2A, 0x00, 0x01])
        pasteboard.clearContents()
        #expect(pasteboard.setData(tiffData, forType: .tiff))
        #expect(
            NativePasteboardContentReader.read(from: pasteboard)
                == .image(
                    PasteboardImageContent(
                        data: tiffData,
                        typeIdentifier: "public.tiff"
                    )
                )
        )

        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let fileItem = NSPasteboardItem()
        fileItem.setString(fixture.file.absoluteString, forType: .fileURL)
        fileItem.setString("secondary text", forType: .string)
        let folderItem = NSPasteboardItem()
        folderItem.setString(fixture.folder.absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([fileItem, folderItem]))
        #expect(
            NativePasteboardContentReader.read(from: pasteboard)
                == .fileURLs([fixture.file, fixture.folder])
        )

        pasteboard.clearContents()
        #expect(pasteboard.setString(" \n\t", forType: .string))
        #expect(NativePasteboardContentReader.read(from: pasteboard) == nil)
    }

    @Test @MainActor
    func routesDirectDropsToAirDropMessagesAndMail() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let fileActions = InMemoryFileCollectionActionService(
            capableDestinations: Set(NativeShareDestination.allCases)
        )
        let model = makeShelfModel(fileActions: fileActions)
        let urls = [fixture.file, fixture.folder]

        for destination in NativeShareDestination.allCases {
            #expect(model.canShare(urls, to: destination))
            await model.share(urls, to: destination)
        }

        #expect(fileActions.namedShares.count == 3)
        let airDrop = try #require(fileActions.namedShares.first)
        let messages = try #require(fileActions.namedShares.dropFirst().first)
        let mail = try #require(fileActions.namedShares.last)
        #expect(airDrop.0 == urls)
        #expect(airDrop.1 == .airDrop)
        #expect(messages.0 == urls)
        #expect(messages.1 == .messages)
        #expect(mail.0 == urls)
        #expect(mail.1 == .mail)
    }

    @Test @MainActor
    func clearWhenEmptyClosesOnlyAfterTheShelfContainedAnItem() throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        var closeCount = 0
        let model = makeShelfModel(
            configuration: ShelfConfiguration(
                clearWhenEmpty: true,
                preferredCorner: .bottomRight,
                playDropSound: false
            ),
            onClose: { closeCount += 1 }
        )

        model.clear()
        #expect(closeCount == 0)
        #expect(model.stage([fixture.file]) == 1)
        let id = try #require(model.items.first?.id)
        model.remove(id)
        #expect(closeCount == 1)
        #expect(model.items.isEmpty)
    }

    @Test @MainActor
    func dropSoundHonorsConfigurationAndOnlyPlaysForAcceptedItems() throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let enabledFeedback = RecordingShelfDropFeedbackPlayer()
        let enabled = makeShelfModel(
            configuration: ShelfConfiguration(
                clearWhenEmpty: false,
                preferredCorner: .bottomRight,
                playDropSound: true
            ),
            dropFeedback: enabledFeedback
        )
        let disabledFeedback = RecordingShelfDropFeedbackPlayer()
        let disabled = makeShelfModel(dropFeedback: disabledFeedback)

        #expect(enabled.stage([fixture.file]) == 1)
        #expect(enabled.stage([fixture.file]) == 0)
        #expect(enabledFeedback.playCount == 1)
        #expect(disabled.stage([fixture.secondFile]) == 1)
        #expect(disabledFeedback.playCount == 0)
    }

    @Test @MainActor
    func removeAndClearNeverDeleteSourceFilesOrFolders() throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let model = makeShelfModel()
        #expect(model.stage([fixture.file, fixture.folder]) == 2)
        let fileID = try #require(model.items.first?.id)

        model.remove(fileID)
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
        model.clear()
        #expect(FileManager.default.fileExists(atPath: fixture.folder.path))
        #expect(model.items.isEmpty)
    }

    @Test @MainActor
    func routesOpenRevealPreviewAndSystemServiceActionsThroughInjectedBoundaries() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let opener = RecordingShelfURLOpener()
        let revealer = InMemoryFileRevealer()
        let preview = InMemoryFilePreviewPresenter()
        let fileActions = InMemoryFileCollectionActionService(
            applicationOptions: [FileActionOption(id: "text-editor", title: "Text Editor")],
            systemSharingOptions: [FileActionOption(id: "photos", title: "Add to Photos")]
        )
        let model = makeShelfModel(
            fileActions: fileActions,
            fileRevealer: revealer,
            urlOpener: opener,
            previewPresenter: preview
        )
        #expect(model.stage([fixture.file, fixture.folder]) == 2)

        await model.openSelected()
        #expect(await opener.urls == [fixture.file, fixture.folder])
        await model.revealSelected()
        #expect(revealer.revealedURLs == [fixture.file, fixture.folder])
        model.previewSelected(startingWith: model.items.last?.id)
        let previewRequest = try #require(preview.requests.first)
        #expect(previewRequest.0 == [fixture.file, fixture.folder])
        #expect(previewRequest.1 == 1)

        await model.refreshOpenWithOptions()
        #expect(model.openWithOptions.map(\.id) == ["text-editor"])
        await model.openSelected(withApplication: "text-editor")
        let openRequest = try #require(fileActions.opened.first)
        #expect(openRequest.0 == [fixture.file, fixture.folder])
        #expect(openRequest.1 == "text-editor")

        await model.refreshSharingOptions()
        #expect(model.sharingOptions.map(\.id) == ["photos"])
        await model.shareSelected(withService: "photos")
        let shareRequest = try #require(fileActions.systemShares.first)
        #expect(shareRequest.0 == [fixture.file, fixture.folder])
        #expect(shareRequest.1 == "photos")
    }

    @Test @MainActor
    func routesDuplicateCopyMoveRenameAndTrashWithoutMutatingRealFiles() async throws {
        let fixture = try ShelfTemporaryFixture()
        defer { fixture.remove() }
        let fileActions = InMemoryFileCollectionActionService(
            chosenDestination: fixture.destination
        )
        let model = makeShelfModel(fileActions: fileActions)

        #expect(model.stage([fixture.file]) == 1)
        await model.duplicateSelected()
        #expect(fileActions.duplicated == [[fixture.file]])
        #expect(model.items.count == 2)

        model.clear()
        #expect(model.stage([fixture.file]) == 1)
        await model.copySelectedToChosenFolder()
        let copyRequest = try #require(fileActions.copied.first)
        #expect(copyRequest.0 == [fixture.file])
        #expect(copyRequest.1 == fixture.destination)

        model.clear()
        #expect(model.stage([fixture.file]) == 1)
        await model.moveSelectedToChosenFolder()
        let moveRequest = try #require(fileActions.moved.first)
        #expect(moveRequest.0 == [fixture.file])
        #expect(moveRequest.1 == fixture.destination)
        let movedID = try #require(model.items.first?.id)
        await model.rename(movedID, to: "Renamed.txt")
        let renameRequest = try #require(fileActions.renamed.first)
        #expect(renameRequest.0 == fixture.destination.appendingPathComponent(fixture.file.lastPathComponent))
        #expect(renameRequest.1 == "Renamed.txt")

        await model.moveSelectedToTrash()
        let trashRequest = try #require(fileActions.trashed.first)
        #expect(trashRequest == [fixture.destination.appendingPathComponent("Renamed.txt")])
        #expect(model.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
    }
}

private func shelfMetadata(
    url: URL,
    isDirectory: Bool = false,
    type: String
) -> FileResourceMetadata {
    FileResourceMetadata(
        url: url,
        displayName: url.lastPathComponent,
        isDirectory: isDirectory,
        contentTypeIdentifier: type
    )
}

@MainActor
private func makeShelfModel(
    entryMode: ShelfEntryMode = .empty,
    configuration: ShelfConfiguration = .default,
    metadata: [FileResourceMetadata] = [],
    fileActions: InMemoryFileCollectionActionService = InMemoryFileCollectionActionService(),
    fileRevealer: any FileRevealing = InMemoryFileRevealer(),
    urlOpener: any URLOpening = NoOpURLOpener(),
    pasteboard: InMemoryPasteboard = InMemoryPasteboard(),
    previewPresenter: InMemoryFilePreviewPresenter = InMemoryFilePreviewPresenter(),
    dropFeedback: any ShelfDropFeedbackPlaying = NoOpShelfDropFeedbackPlayer(),
    temporaryContentStore: any ShelfTemporaryContentStoring = InMemoryShelfTemporaryContentStore(),
    onClose: @escaping () -> Void = {}
) -> ShelfBoardModel {
    ShelfBoardModel(
        entryMode: entryMode,
        configuration: configuration,
        services: ShelfApplicationServices(
            metadataReader: InMemoryFileResourceMetadataReader(metadata: metadata),
            fileActions: fileActions,
            fileRevealer: fileRevealer,
            urlOpener: urlOpener,
            pasteboard: pasteboard,
            previewPresenter: previewPresenter,
            dropFeedback: dropFeedback,
            makeTemporaryContentStore: {
                temporaryContentStore
            }
        ),
        onClose: onClose
    )
}

@MainActor
private func yieldUntil(
    maxYields: Int = 100,
    condition: @MainActor () -> Bool
) async {
    for _ in 0..<maxYields {
        if condition() { return }
        await Task.yield()
    }
}

@MainActor
private func yieldUntilStoreSnapshot(
    _ store: InMemoryShelfTemporaryContentStore,
    maxYields: Int = 100,
    condition: (InMemoryShelfTemporaryContentStore.Snapshot) -> Bool
) async -> InMemoryShelfTemporaryContentStore.Snapshot {
    var snapshot = await store.snapshot()
    for _ in 0..<maxYields where condition(snapshot) == false {
        await Task.yield()
        snapshot = await store.snapshot()
    }
    return snapshot
}

@MainActor
private final class RecordingShelfDropFeedbackPlayer: ShelfDropFeedbackPlaying {
    private(set) var playCount = 0

    func playDropAccepted() {
        playCount += 1
    }
}

private actor RecordingShelfURLOpener: URLOpening {
    private(set) var urls: [URL] = []

    func openURL(_ url: URL) async throws {
        urls.append(url)
    }
}

private struct ShelfTemporaryFixture {
    let root: URL
    let file: URL
    let secondFile: URL
    let folder: URL
    let destination: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Commandly-ShelfTests-\(UUID().uuidString)", isDirectory: true)
        file = root.appendingPathComponent("Notes.txt")
        secondFile = root.appendingPathComponent("Schedule.csv")
        folder = root.appendingPathComponent("Reference", isDirectory: true)
        destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("shelf fixture".utf8).write(to: file)
        try Data("date,title".utf8).write(to: secondFile)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
