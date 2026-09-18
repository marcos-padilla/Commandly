import CommandKit
import Infrastructure
import SwiftUI

/// Converts and reads explicitly selected images using native, local codecs and Vision.
@MainActor
struct ImageToolsApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "images.tools")
    static let openToolID = CommandID(rawValue: "images.tools.open")
    static let chooseImageToolID = CommandID(rawValue: "images.tools.choose")
    static let extractTextToolID = CommandID(rawValue: "images.tools.extract-text")
    static let decodeQRToolID = CommandID(rawValue: "images.tools.decode-qr")

    static let manifest = CommandManifest(
        id: applicationID, title: "Image Tools", subtitle: "Convert images, extract text, and decode QR codes locally",
        systemImage: "photo.badge.arrow.down", category: .productivity, mode: .view,
        keywords: ["convert image", "image converter", "resize image", "rotate", "photo", "png", "jpeg", "jpg", "heic", "tiff", "OCR", "extract text", "QR code"],
        badgeTitle: "Application",
        defaultActions: [CommandActionDescriptor(id: ImageToolsActionID.choose, title: "Choose Image", isPrimary: true, keyHint: .return)]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 39, documentation: RegisteredApplicationDocumentation.imageTools
    )

    private let converter: any ImageConverting
    private let recognizer: any ImageRecognizing
    private let pasteboard: any PasteboardAccessing
    private let urlOpener: any URLOpening

    init(converter: any ImageConverting, recognizer: any ImageRecognizing,
         pasteboard: any PasteboardAccessing, urlOpener: any URLOpening) {
        self.converter = converter
        self.recognizer = recognizer
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            .tool(id: Self.openToolID, parentID: Self.applicationID, title: "Open Image Tools",
                  subtitle: "Convert, resize, and rotate images locally", systemImage: "photo.badge.arrow.down",
                  keywords: ["image", "convert", "resize", "rotate", "png", "jpeg", "heic", "tiff"]),
            .tool(id: Self.chooseImageToolID, parentID: Self.applicationID, title: "Choose Image to Convert",
                  subtitle: "Pick one image for Image Tools", systemImage: "photo.on.rectangle", order: 1,
                  keywords: ["choose image", "convert image", "resize photo"]),
            .tool(id: Self.extractTextToolID, parentID: Self.applicationID, title: "Extract Text from Image",
                  subtitle: "Read and copy image text on this Mac", systemImage: "text.viewfinder", order: 2,
                  keywords: ["OCR", "extract text", "image to text", "copy text", "read screenshot"]),
            .tool(id: Self.decodeQRToolID, parentID: Self.applicationID, title: "Decode QR from Image",
                  subtitle: "Review and copy QR code contents", systemImage: "qrcode.viewfinder", order: 3,
                  keywords: ["decode QR", "QR code", "read QR", "scan code"])
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(choosesImage: false, context: context)
    }

    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case Self.openToolID: return makeLaunch(choosesImage: false, context: context)
        case Self.chooseImageToolID: return makeLaunch(choosesImage: true, context: context)
        case Self.extractTextToolID: return makeLaunch(choosesImage: true, mode: .text, context: context)
        case Self.decodeQRToolID: return makeLaunch(choosesImage: true, mode: .qr, context: context)
        default: return .message("Image Tools entry is unavailable.")
        }
    }

    private func makeLaunch(choosesImage: Bool, mode: ImageToolsMode = .convert, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let inspection = ImageInspectionViewModel(recognizer: recognizer, pasteboard: pasteboard, urlOpener: urlOpener)
        let model = ImageToolsViewModel(converter: converter, inspection: inspection, onGoBack: context.navigation.goBack)
        model.mode = mode
        model.showsImageImporter = choosesImage
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            ImageToolsView(viewModel: $0)
        })
    }
}
