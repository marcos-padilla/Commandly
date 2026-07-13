import AppKit
import Infrastructure

/// Non-secret behavior resolved from Shelf's generic Applications settings schema.
struct ShelfConfiguration: Sendable, Equatable {
    var keepVisibleWhenInactive: Bool
    var clearWhenEmpty: Bool
    var preferredCorner: ShelfPreferredCorner
    var playDropSound: Bool

    static let `default` = ShelfConfiguration(
        keepVisibleWhenInactive: true,
        clearWhenEmpty: false,
        preferredCorner: .bottomRight,
        playDropSound: false
    )
}

/// Optional local feedback for a successfully accepted Shelf drop.
@MainActor
protocol ShelfDropFeedbackPlaying: Sendable {
    func playDropAccepted()
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

    init(
        metadataReader: any FileResourceMetadataReading,
        fileActions: any FileCollectionActionServicing,
        fileRevealer: any FileRevealing,
        urlOpener: any URLOpening,
        pasteboard: any PasteboardAccessing,
        previewPresenter: any FilePreviewPresenting,
        dropFeedback: any ShelfDropFeedbackPlaying
    ) {
        self.metadataReader = metadataReader
        self.fileActions = fileActions
        self.fileRevealer = fileRevealer
        self.urlOpener = urlOpener
        self.pasteboard = pasteboard
        self.previewPresenter = previewPresenter
        self.dropFeedback = dropFeedback
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
