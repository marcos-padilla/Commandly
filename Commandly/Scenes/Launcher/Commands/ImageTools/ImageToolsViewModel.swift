import CommandKit
import Foundation
import Infrastructure
import Observation

enum ImageToolsActionID {
    static let choose = CommandActionID(rawValue: "image-tools.choose")
    static let convert = CommandActionID(rawValue: "image-tools.convert")
    static let save = CommandActionID(rawValue: "image-tools.save")
    static let clear = CommandActionID(rawValue: "image-tools.clear")
    static let cancel = CommandActionID(rawValue: "image-tools.cancel")
}

enum ImageToolsMode: String, CaseIterable, Identifiable {
    case convert, text, qr
    var id: String { rawValue }
    var title: String {
        switch self {
        case .convert: "Convert"
        case .text: "Extract Text"
        case .qr: "Decode QR"
        }
    }
    var recognitionMode: ImageRecognitionMode? {
        switch self {
        case .convert: nil
        case .text: .text
        case .qr: .qr
        }
    }
}

@Observable
@MainActor
final class ImageToolsViewModel: LauncherApplicationModel {
    @ObservationIgnored private let converter: any ImageConverting
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    let inspection: ImageInspectionViewModel?

    private(set) var source: ImageConversionSource?
    private(set) var result: ImageConversionResult?
    private(set) var supportedFormats: [ImageConversionFormat] = []
    private(set) var isWorking = false
    private var conversionStatusMessage: String?
    private(set) var statusMessage: String? {
        get {
            mode == .convert || isWorking ? conversionStatusMessage : inspection?.statusMessage ?? conversionStatusMessage
        }
        set { conversionStatusMessage = newValue }
    }
    private(set) var errorMessage: String?
    var showsActionsMenu = false
    var showsImageImporter = false
    var showsFileExporter = false
    var format: ImageConversionFormat = .png { didSet { settingsChanged() } }
    var resizesImage = false { didSet { settingsChanged() } }
    var longestEdgeText = "1600" { didSet { settingsChanged() } }
    var clockwiseQuarterTurns = 0 { didSet { settingsChanged() } }
    var mode: ImageToolsMode = .convert {
        didSet {
            guard mode != oldValue else { return }
            cancelWork()
            inspection?.stop()
            result = nil
            errorMessage = nil
            showsFileExporter = false
            statusMessage = nil
            analyzeCurrentImage()
        }
    }

    init(converter: any ImageConverting, inspection: ImageInspectionViewModel? = nil, onGoBack: @escaping () -> Void) {
        self.converter = converter
        self.inspection = inspection
        self.onGoBack = onGoBack
    }

    deinit { work?.cancel() }

    var canConvert: Bool { mode == .convert && source != nil && isWorking == false && options != nil && supportedFormats.contains(format) }

    var options: ImageConversionOptions? {
        let edge = Int(longestEdgeText.trimmingCharacters(in: .whitespacesAndNewlines))
        if resizesImage, edge.map({ (1...16_384).contains($0) }) != true { return nil }
        return ImageConversionOptions(format: format, longestEdge: resizesImage ? edge : nil, clockwiseQuarterTurns: clockwiseQuarterTurns)
    }

    var suggestedFilename: String {
        let original = ((source?.filename ?? "image") as NSString).deletingPathExtension
        let prohibited = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let cleaned = String(original.unicodeScalars.map { prohibited.contains($0) ? "-" : String($0) }.joined().prefix(100))
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(cleaned.isEmpty ? "image" : cleaned)-converted.\((result?.format ?? format).filenameExtension)"
    }

    var footerActions: [CommandActionDescriptor] {
        if isWorking {
            return [CommandActionDescriptor(id: ImageToolsActionID.cancel, title: "Cancel", isPrimary: true, keyHint: .escape)]
        }
        if mode != .convert, source != nil, let inspection { return inspection.footerActions }
        let primary: CommandActionDescriptor
        if result != nil {
            primary = CommandActionDescriptor(id: ImageToolsActionID.save, title: "Save Image", isPrimary: true, keyHint: .return)
        } else if source != nil {
            primary = CommandActionDescriptor(id: ImageToolsActionID.convert, title: "Convert Image", isPrimary: true, keyHint: .return, isEnabled: canConvert)
        } else {
            primary = CommandActionDescriptor(id: ImageToolsActionID.choose, title: "Choose Image", isPrimary: true, keyHint: .return)
        }
        return [primary, CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }

    var menuActions: [CommandActionDescriptor] {
        if mode != .convert, let inspection {
            return [CommandActionDescriptor(id: ImageToolsActionID.choose, title: "Choose Image")]
                + inspection.menuActions
                + [CommandActionDescriptor(id: ImageToolsActionID.clear, title: "Clear Image", isEnabled: source != nil || isWorking)]
        }
        return [
            CommandActionDescriptor(id: ImageToolsActionID.choose, title: "Choose Image"),
            CommandActionDescriptor(id: ImageToolsActionID.convert, title: "Convert Image", isEnabled: canConvert),
            CommandActionDescriptor(id: ImageToolsActionID.save, title: "Save Image", isEnabled: result != nil),
            CommandActionDescriptor(id: ImageToolsActionID.clear, title: "Clear Image", isEnabled: source != nil || isWorking)
        ]
    }

    func load(_ url: URL) {
        cancelWork()
        inspection?.stop()
        let request = generation
        source = nil
        result = nil
        errorMessage = nil
        showsFileExporter = false
        isWorking = true
        statusMessage = "Reading image on this Mac…"
        work = Task { [weak self, converter] in
            do {
                let formats = await converter.supportedFormats()
                let loaded = try await converter.loadImage(from: url)
                try Task.checkCancellation()
                guard let self, generation == request else { return }
                supportedFormats = formats
                if formats.contains(format) == false, let first = formats.first { format = first }
                source = loaded
                isWorking = false
                statusMessage = "Choose an output format, review your settings, then convert."
                analyzeCurrentImage()
            } catch {
                self?.finishFailure(error, request: request)
            }
        }
    }

    func convert() {
        guard let source, let options, canConvert else { return }
        cancelWork()
        let request = generation
        isWorking = true
        result = nil
        errorMessage = nil
        statusMessage = "Converting image on this Mac…"
        work = Task { [weak self, converter] in
            do {
                let converted = try await converter.convert(source, options: options)
                try Task.checkCancellation()
                guard let self, generation == request else { return }
                result = converted
                isWorking = false
                statusMessage = "Conversion ready. Review the preview and save your image."
            } catch {
                self?.finishFailure(error, request: request)
            }
        }
    }

    func analyzeCurrentImage() {
        guard let source, let mode = mode.recognitionMode else { return }
        inspection?.analyze(source, mode: mode)
    }

    func importCompleted(_ selection: Result<[URL], Error>) {
        switch selection {
        case .success(let urls):
            if let url = urls.first { load(url) }
        case .failure(let error):
            guard Self.isUserCancellation(error) == false else { return }
            errorMessage = "The image couldn’t be opened. Choose it again and check file access."
            statusMessage = errorMessage
        }
    }

    func exportCompleted(_ export: Result<URL, Error>) {
        switch export {
        case .success:
            statusMessage = "Converted image saved."
            errorMessage = nil
        case .failure(let error):
            guard Self.isUserCancellation(error) == false else { return }
            errorMessage = "The image couldn’t be saved. Choose another location and try again."
            statusMessage = errorMessage
        }
    }

    func goBack() { onGoBack() }
    func moveSelection(offset: Int) {
        if mode != .convert { inspection?.moveSelection(offset: offset) }
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case ImageToolsActionID.choose: showsImageImporter = true
        case ImageToolsActionID.convert: convert()
        case ImageToolsActionID.save: if result != nil { showsFileExporter = true }
        case ImageToolsActionID.clear: stop()
        case ImageToolsActionID.cancel:
            if mode != .convert, isWorking == false {
                inspection?.cancel()
            } else {
                cancelWork()
                statusMessage = "Image processing cancelled."
            }
        case ImageInspectionActionID.copy: inspection?.copySelection()
        case ImageInspectionActionID.reviewLink: inspection?.reviewSelectedLink()
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }

    func stop() {
        cancelWork()
        inspection?.stop()
        source = nil
        result = nil
        errorMessage = nil
        statusMessage = nil
        showsImageImporter = false
        showsFileExporter = false
        showsActionsMenu = false
    }

    func handleEscape() -> Bool {
        if inspection?.pendingURLReview != nil { inspection?.pendingURLReview = nil; return true }
        if showsFileExporter { showsFileExporter = false; return true }
        if showsImageImporter { showsImageImporter = false; return true }
        if isWorking { perform(ImageToolsActionID.cancel); return true }
        if mode != .convert, inspection?.isWorking == true { inspection?.cancel(); return true }
        return false
    }

    func waitForWorkForTesting() async { await work?.value }
    func pendingWorkForTesting() -> Task<Void, Never>? { work }

    private func settingsChanged() {
        result = nil
        showsFileExporter = false
        errorMessage = nil
        if source != nil {
            cancelWork()
            statusMessage = "Settings changed. Convert again to update the preview."
        }
    }

    private func cancelWork() {
        work?.cancel()
        work = nil
        generation += 1
        isWorking = false
    }

    private func finishFailure(_ error: Error, request: Int) {
        guard generation == request else { return }
        isWorking = false
        if error is CancellationError {
            statusMessage = "Image processing cancelled."
        } else {
            errorMessage = Self.message(for: error)
            statusMessage = errorMessage
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }

    private static func message(for error: Error) -> String {
        switch error as? ImageConversionError {
        case .fileReadFailed: "Commandly couldn’t read that file. Choose it again and check file access."
        case .invalidImage: "That file isn’t a supported image. Try a PNG, JPEG, HEIC, or TIFF."
        case .animatedImageUnsupported: "Choose a single still image. Animated and multi-page images are not supported."
        case .inputTooLarge: "Choose an image up to 64 MB, 40 megapixels, and 16,384 pixels per side."
        case .invalidDimensions: "Enter a longest edge from 1 to 16,384 pixels."
        case .outputTooLarge: "The output is too large. Resize to fewer pixels and try again."
        case .unsupportedFormat: "This Mac can’t encode that format. Choose another output format."
        case .encodingFailed: "The image couldn’t be encoded. Choose another format and try again."
        case nil: "The image couldn’t be processed. Choose it again and try another format."
        }
    }
}
