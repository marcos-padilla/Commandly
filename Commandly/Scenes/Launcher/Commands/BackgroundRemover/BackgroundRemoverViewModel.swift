import CommandKit
import Foundation
import Infrastructure
import Observation

enum BackgroundRemoverActionID {
    static let chooseImage = CommandActionID(rawValue: "background-remover.choose-image")
    static let savePNG = CommandActionID(rawValue: "background-remover.save-png")
    static let reset = CommandActionID(rawValue: "background-remover.reset")
    static let cancel = CommandActionID(rawValue: "background-remover.cancel")
}

enum BackgroundRemoverState: Equatable {
    case empty
    case processing(filename: String)
    case completed(BackgroundRemovalResult)
    case failed(filename: String, message: String)
}

@Observable
@MainActor
final class BackgroundRemoverViewModel: LauncherApplicationModel {
    @ObservationIgnored private let remover: any BackgroundRemoving
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var processingGeneration = 0

    private(set) var state: BackgroundRemoverState = .empty
    private(set) var statusMessage: String?
    var showsActionsMenu = false
    var showsImageImporter = false
    var showsFileExporter = false

    init(
        remover: any BackgroundRemoving,
        onGoBack: @escaping () -> Void
    ) {
        self.remover = remover
        self.onGoBack = onGoBack
    }

    deinit {
        processingTask?.cancel()
    }

    var result: BackgroundRemovalResult? {
        guard case .completed(let result) = state else { return nil }
        return result
    }

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    var suggestedFilename: String {
        guard let result else { return "background-removed.png" }
        let stem = (result.sourceFilename as NSString).deletingPathExtension
        let safeStem = stem.isEmpty ? "image" : stem
        return "\(safeStem)-background-removed.png"
    }

    var footerActions: [CommandActionDescriptor] {
        switch state {
        case .empty, .failed:
            return [
                CommandActionDescriptor(
                    id: BackgroundRemoverActionID.chooseImage,
                    title: "Choose Image",
                    isPrimary: true,
                    keyHint: .return
                )
            ]
        case .processing:
            return [
                CommandActionDescriptor(
                    id: BackgroundRemoverActionID.cancel,
                    title: "Cancel",
                    isPrimary: true,
                    keyHint: .escape
                )
            ]
        case .completed:
            return [
                CommandActionDescriptor(
                    id: BackgroundRemoverActionID.savePNG,
                    title: "Save PNG",
                    isPrimary: true,
                    keyHint: .return
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openActions,
                    title: "Actions",
                    keyHint: .commandK
                )
            ]
        }
    }

    var menuActions: [CommandActionDescriptor] {
        var actions = [
            CommandActionDescriptor(
                id: BackgroundRemoverActionID.chooseImage,
                title: result == nil ? "Choose Image" : "Choose Another Image",
                isEnabled: isProcessing == false
            )
        ]
        if result != nil {
            actions.insert(
                CommandActionDescriptor(
                    id: BackgroundRemoverActionID.savePNG,
                    title: "Save Transparent PNG",
                    isPrimary: true
                ),
                at: 0
            )
            actions.append(
                CommandActionDescriptor(
                    id: BackgroundRemoverActionID.reset,
                    title: "Clear Image"
                )
            )
        }
        return actions
    }

    func process(_ sourceURL: URL) {
        processingTask?.cancel()
        processingGeneration += 1
        let generation = processingGeneration
        let filename = sourceURL.lastPathComponent
        state = .processing(filename: filename)
        statusMessage = "Removing the background on this Mac…"

        processingTask = Task { [weak self, remover] in
            do {
                let result = try await remover.removeBackground(from: sourceURL)
                try Task.checkCancellation()
                guard let self, generation == self.processingGeneration else { return }
                self.state = .completed(result)
                self.statusMessage = "Background removed. The transparent PNG is ready to save."
            } catch is CancellationError {
                guard let self, generation == self.processingGeneration else { return }
                self.state = .empty
                self.statusMessage = "Background removal cancelled."
            } catch {
                guard let self, generation == self.processingGeneration else { return }
                let message = Self.message(for: error)
                self.state = .failed(filename: filename, message: message)
                self.statusMessage = message
            }
        }
    }

    func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            statusMessage = "Transparent PNG saved."
        case .failure(let error):
            if (error as NSError).code == NSUserCancelledError {
                return
            }
            statusMessage = "The PNG couldn’t be saved. Choose another location and try again."
        }
    }

    func goBack() {
        onGoBack()
    }

    func moveSelection(offset: Int) {
        _ = offset
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case BackgroundRemoverActionID.chooseImage:
            showsImageImporter = true
        case BackgroundRemoverActionID.savePNG:
            if result != nil { showsFileExporter = true }
        case BackgroundRemoverActionID.reset:
            reset()
        case BackgroundRemoverActionID.cancel:
            cancelProcessing()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu = true
        default:
            break
        }
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        processingGeneration += 1
        state = .empty
        statusMessage = nil
        showsImageImporter = false
        showsFileExporter = false
        showsActionsMenu = false
    }

    func handleEscape() -> Bool {
        if showsImageImporter {
            showsImageImporter = false
            return true
        }
        if isProcessing {
            cancelProcessing()
            return true
        }
        return false
    }

    func waitForProcessingForTesting() async {
        await processingTask?.value
    }

    private func reset() {
        processingTask?.cancel()
        processingTask = nil
        processingGeneration += 1
        state = .empty
        statusMessage = nil
    }

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        processingGeneration += 1
        state = .empty
        statusMessage = "Background removal cancelled."
    }

    private static func message(for error: Error) -> String {
        switch error as? BackgroundRemovalError {
        case .invalidImage:
            return "That file isn’t a supported image. Try a PNG, JPEG, HEIC, or TIFF file."
        case .noForegroundFound:
            return "No distinct foreground subject was found. Try an image with a clearer subject."
        case .segmentationFailed:
            return "The on-device model couldn’t separate this image. Try a different image."
        case .encodingFailed:
            return "The transparent result couldn’t be encoded as a PNG."
        case .fileReadFailed:
            return "Commandly couldn’t read that image. Check its access and try again."
        case nil:
            return "The background couldn’t be removed. Try a different image."
        }
    }
}
