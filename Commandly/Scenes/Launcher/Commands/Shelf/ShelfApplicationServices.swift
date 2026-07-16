import AppCore
import AppKit
import Infrastructure

/// Non-secret behavior resolved from Shelf's generic Applications settings schema.
struct ShelfConfiguration: Sendable, Equatable {
    var clearWhenEmpty: Bool
    var preferredCorner: ShelfPreferredCorner
    var playDropSound: Bool

    static let `default` = ShelfConfiguration(
        clearWhenEmpty: false,
        preferredCorner: ShelfPreferredCorner.defaultValue,
        playDropSound: false
    )
}

/// Optional local feedback for a successfully accepted Shelf drop.
@MainActor
protocol ShelfDropFeedbackPlaying: Sendable {
    func playDropAccepted()
}

/// Per-board private storage for clipboard text and image materialized as temporary files.
nonisolated protocol ShelfTemporaryContentStoring: Sendable {
    func createTextFile(containing text: String) async throws -> URL
    func createImageFile(_ image: PasteboardImageContent) async throws -> URL
    func discard(_ urls: [URL]) async
    func discardAll() async
}

/// Controllable board-owned temporary storage for tests and previews.
actor InMemoryShelfTemporaryContentStore: ShelfTemporaryContentStoring {
    struct Snapshot: Sendable, Equatable {
        let textValues: [String]
        let imageValues: [PasteboardImageContent]
        let discardedURLs: [URL]
        let discardAllCount: Int
    }

    private let textFileURL: URL?
    private let imageFileURL: URL?
    private var textValues: [String] = []
    private var imageValues: [PasteboardImageContent] = []
    private var discardedURLs: [URL] = []
    private var discardAllCount = 0

    init(textFileURL: URL? = nil, imageFileURL: URL? = nil) {
        self.textFileURL = textFileURL
        self.imageFileURL = imageFileURL
    }

    func createTextFile(containing text: String) throws -> URL {
        guard let textFileURL else {
            throw CommandlyError.unsupported("Clipboard text materialization is unavailable.")
        }
        textValues.append(text)
        return textFileURL
    }

    func createImageFile(_ image: PasteboardImageContent) throws -> URL {
        guard let imageFileURL else {
            throw CommandlyError.unsupported("Clipboard image materialization is unavailable.")
        }
        imageValues.append(image)
        return imageFileURL
    }

    func discard(_ urls: [URL]) {
        discardedURLs.append(contentsOf: urls)
    }

    func discardAll() {
        discardAllCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            textValues: textValues,
            imageValues: imageValues,
            discardedURLs: discardedURLs,
            discardAllCount: discardAllCount
        )
    }
}

/// Focused dependency group for one temporary Shelf board.
struct ShelfApplicationServices {
    let metadataReader: any FileResourceMetadataReading
    let fileActions: any FileCollectionActionServicing
    let fileRevealer: any FileRevealing
    let urlOpener: any URLOpening
    let pasteboard: any PasteboardAccessing
    let previewPresenter: any FilePreviewPresenting
    let dropFeedback: any ShelfDropFeedbackPlaying
    let makeTemporaryContentStore: @MainActor () -> any ShelfTemporaryContentStoring

    init(
        metadataReader: any FileResourceMetadataReading,
        fileActions: any FileCollectionActionServicing,
        fileRevealer: any FileRevealing,
        urlOpener: any URLOpening,
        pasteboard: any PasteboardAccessing,
        previewPresenter: any FilePreviewPresenting,
        dropFeedback: any ShelfDropFeedbackPlaying,
        makeTemporaryContentStore: @escaping @MainActor () -> any ShelfTemporaryContentStoring
    ) {
        self.metadataReader = metadataReader
        self.fileActions = fileActions
        self.fileRevealer = fileRevealer
        self.urlOpener = urlOpener
        self.pasteboard = pasteboard
        self.previewPresenter = previewPresenter
        self.dropFeedback = dropFeedback
        self.makeTemporaryContentStore = makeTemporaryContentStore
    }
}

extension NativeShareDestination {
    var shelfTitle: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .messages: return "Messages"
        case .mail: return "Mail"
        }
    }

    var shelfSystemImage: String {
        switch self {
        case .airDrop: return "airdrop"
        case .messages: return "message.fill"
        case .mail: return "envelope.fill"
        }
    }

    var appKitSharingServiceName: NSSharingService.Name {
        switch self {
        case .airDrop: return .sendViaAirDrop
        case .messages: return .composeMessage
        case .mail: return .composeEmail
        }
    }

    var shelfNativeImage: NSImage? {
        NSSharingService(named: appKitSharingServiceName)?.image
    }
}
