import CommandKit
import Foundation
import Infrastructure
import Observation

enum ImageInspectionActionID {
    static let copy = CommandActionID(rawValue: "image-tools.inspection.copy")
    static let reviewLink = CommandActionID(rawValue: "image-tools.inspection.review-link")
}

/// Recognition and review state kept separate from conversion settings and export state.
@Observable
@MainActor
final class ImageInspectionViewModel {
    @ObservationIgnored private let recognizer: any ImageRecognizing
    @ObservationIgnored private let pasteboard: any PasteboardAccessing
    @ObservationIgnored private let urlOpener: any URLOpening
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private(set) var result: ImageRecognitionResult?
    private(set) var mode: ImageRecognitionMode = .text
    private(set) var isWorking = false
    private(set) var isPerformingAction = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var selectedPayloadIndex: Int?
    var pendingURLReview: ImageQRURLReview?
    var reviewedText = "" {
        didSet {
            if reviewedText.count > ImageRecognitionOutput.maximumCharacters {
                reviewedText = String(reviewedText.prefix(ImageRecognitionOutput.maximumCharacters))
                statusMessage = "Text is limited to 64,000 characters."
            }
        }
    }

    init(recognizer: any ImageRecognizing, pasteboard: any PasteboardAccessing, urlOpener: any URLOpening) {
        self.recognizer = recognizer
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener
    }

    deinit { work?.cancel(); action?.cancel() }

    var selectedPayload: String? {
        guard let index = selectedPayloadIndex, let payloads = result?.qrPayloads, payloads.indices.contains(index) else { return nil }
        return payloads[index]
    }

    var canCopy: Bool {
        guard isWorking == false, isPerformingAction == false else { return false }
        return mode == .text ? reviewedText.isEmpty == false : selectedPayload != nil
    }

    var canReviewLink: Bool {
        guard mode == .qr, isWorking == false, isPerformingAction == false, let selectedPayload else { return false }
        return ImageQRURLReview.make(for: selectedPayload) != nil
    }

    var footerActions: [CommandActionDescriptor] {
        if isWorking {
            return [CommandActionDescriptor(id: ImageToolsActionID.cancel, title: "Cancel", isPrimary: true, keyHint: .escape)]
        }
        return [
            CommandActionDescriptor(id: ImageInspectionActionID.copy, title: mode == .text ? "Copy Text" : "Copy QR Content",
                                    isPrimary: true, keyHint: .return, isEnabled: canCopy),
            CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(id: ImageInspectionActionID.copy, title: mode == .text ? "Copy Text" : "Copy QR Content", isEnabled: canCopy),
            CommandActionDescriptor(id: ImageInspectionActionID.reviewLink, title: "Review Web Link", isEnabled: canReviewLink)
        ]
    }

    func analyze(_ source: ImageConversionSource, mode: ImageRecognitionMode) {
        stop()
        self.mode = mode
        let request = generation
        isWorking = true
        statusMessage = mode == .text ? "Reading text on this Mac…" : "Decoding QR codes on this Mac…"
        work = Task { [weak self, recognizer] in
            do {
                let recognized = try await recognizer.recognize(source, mode: mode)
                try Task.checkCancellation()
                guard let self, request == generation else { return }
                result = recognized
                reviewedText = recognized.text
                selectedPayloadIndex = recognized.qrPayloads.isEmpty ? nil : 0
                isWorking = false
                statusMessage = Self.completionMessage(recognized, mode: mode)
            } catch is CancellationError {
                guard let self, request == generation else { return }
                isWorking = false
                statusMessage = "Image recognition cancelled."
            } catch {
                guard let self, request == generation else { return }
                isWorking = false
                errorMessage = "This image couldn’t be read. Try a clearer image or choose it again."
                statusMessage = errorMessage
            }
        }
    }

    func selectPayload(at index: Int) {
        guard let payloads = result?.qrPayloads, payloads.indices.contains(index) else { return }
        selectedPayloadIndex = index
        pendingURLReview = nil
    }

    func moveSelection(offset: Int) {
        guard mode == .qr, let payloads = result?.qrPayloads, payloads.isEmpty == false else { return }
        let count = payloads.count
        let next = ((selectedPayloadIndex ?? 0) + offset % count + count) % count
        selectPayload(at: next)
    }

    func copySelection() {
        guard canCopy, let value = mode == .text ? reviewedText : selectedPayload else { return }
        let request = generation
        isPerformingAction = true
        action = Task { [weak self, pasteboard] in
            guard Task.isCancelled == false else { return }
            await pasteboard.writeString(value)
            guard let self, request == generation, Task.isCancelled == false else { return }
            isPerformingAction = false
            statusMessage = mode == .text ? "Text copied." : "QR content copied."
        }
    }

    func reviewSelectedLink() {
        guard canReviewLink, let selectedPayload else { return }
        pendingURLReview = ImageQRURLReview.make(for: selectedPayload)
    }

    func openReviewedLink() {
        guard isPerformingAction == false,
              let review = pendingURLReview,
              review.payload == selectedPayload,
              ImageQRURLReview.make(for: review.payload) == review else { return }
        pendingURLReview = nil
        let request = generation
        isPerformingAction = true
        action = Task { [weak self, urlOpener] in
            do {
                try Task.checkCancellation()
                try await urlOpener.openURL(review.url)
                try Task.checkCancellation()
                guard let self, request == generation else { return }
                isPerformingAction = false
                errorMessage = nil
                statusMessage = "Web link opened."
            } catch {
                guard let self, request == generation else { return }
                isPerformingAction = false
                guard error is CancellationError == false else { return }
                errorMessage = "The web link couldn’t be opened. You can copy it or review it again."
                statusMessage = errorMessage
            }
        }
    }

    func cancel() {
        stop()
        statusMessage = "Image recognition cancelled."
    }

    func stop() {
        work?.cancel()
        action?.cancel()
        work = nil
        action = nil
        generation += 1
        isWorking = false
        isPerformingAction = false
        result = nil
        reviewedText = ""
        selectedPayloadIndex = nil
        pendingURLReview = nil
        errorMessage = nil
        statusMessage = nil
    }

    func waitForWorkForTesting() async { await work?.value }
    func waitForActionForTesting() async { await action?.value }
    func pendingWorkForTesting() -> Task<Void, Never>? { work }

    private static func completionMessage(_ result: ImageRecognitionResult, mode: ImageRecognitionMode) -> String {
        if mode == .text {
            return result.text.isEmpty ? "No readable text found. Try a clearer image." : "Review or edit the recognized text, then copy it."
        }
        if result.qrPayloads.isEmpty {
            return result.nonTextQRCodeCount > 0
                ? "QR codes were detected, but their contents aren’t readable text."
                : "No QR code found. Try a sharper image that includes the whole code."
        }
        return "QR content is ready to review. Copying and opening links are separate actions."
    }
}
