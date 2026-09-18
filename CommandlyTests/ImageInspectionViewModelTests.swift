import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct ImageInspectionViewModelTests {
    @Test
    func extractedTextStaysInReviewUntilExplicitCopyAndEditsArePreserved() async {
        let actions = ImageInspectionActions()
        let recognizer = ImageInspectionRecognizer(result: ImageRecognitionResult(text: "Recognized text"))
        let model = ImageInspectionViewModel(recognizer: recognizer, pasteboard: actions, urlOpener: actions)
        model.analyze(Self.source, mode: .text)
        await model.waitForWorkForTesting()
        #expect(model.reviewedText == "Recognized text")
        #expect(await actions.copiedStrings().isEmpty)
        #expect(await actions.openedURLs().isEmpty)
        #expect(await actions.reads() == 0)
        model.reviewedText = "  Corrected\ntext  "
        model.copySelection()
        await model.waitForActionForTesting()
        #expect(await actions.copiedStrings() == ["  Corrected\ntext  "])
        model.reviewedText = String(repeating: "x", count: 64_001)
        #expect(model.reviewedText.count == 64_000)
        model.stop()
        #expect(model.reviewedText.isEmpty && model.result == nil)
    }

    @Test
    func QRRequiresSelectionReviewAndSeparateConfirmationBeforeOpening() async throws {
        let actions = ImageInspectionActions()
        let payloads = ["https://example.invalid/first", "WIFI:S:Example;T:WPA;P:secret;;"]
        let model = ImageInspectionViewModel(
            recognizer: ImageInspectionRecognizer(result: ImageRecognitionResult(qrPayloads: payloads)),
            pasteboard: actions, urlOpener: actions
        )
        model.analyze(Self.source, mode: .qr)
        await model.waitForWorkForTesting()
        #expect(model.canCopy && model.canReviewLink)
        #expect(model.footerActions.first?.id == ImageInspectionActionID.copy)
        model.openReviewedLink()
        #expect(await actions.openedURLs().isEmpty)
        model.reviewSelectedLink()
        let review = try #require(model.pendingURLReview)
        #expect(review.host == "example.invalid")
        #expect(await actions.openedURLs().isEmpty)
        model.selectPayload(at: 1)
        #expect(model.pendingURLReview == nil && model.canReviewLink == false)
        model.pendingURLReview = review
        model.openReviewedLink()
        #expect(await actions.openedURLs().isEmpty)
        model.copySelection()
        await model.waitForActionForTesting()
        #expect(await actions.copiedStrings() == [payloads[1]])
        model.moveSelection(offset: -1)
        model.reviewSelectedLink()
        model.openReviewedLink()
        model.openReviewedLink()
        await model.waitForActionForTesting()
        #expect(await actions.openedURLs().map(\.absoluteString) == [payloads[0]])
        #expect(model.pendingURLReview == nil)
    }

    @Test
    func URLReviewAcceptsOnlyWellFormedCredentialFreeWebLinks() {
        for invalid in [
            "javascript:alert(1)", "data:text/html,test", "file:///tmp/image", "mailto:test@example.invalid",
            "commandly://action", "WIFI:S:network;;", "https://user:password@example.invalid",
            "https://@example.invalid", "https:///path", "example.invalid", "https://example.invalid:0/a",
            " https://example.invalid", "https://example.invalid/a\nb", "https://example.invalid/%0Afoo",
            "https://example.invalid\\@other.invalid", "https://example.invalid/\u{202E}evil"
        ] {
            #expect(ImageQRURLReview.make(for: invalid) == nil)
        }
        #expect(ImageQRURLReview.make(for: "https://example.invalid/path?q=a%20b#section") != nil)
        #expect(ImageQRURLReview.make(for: "http://127.0.0.1:8080/path") != nil)
    }

    @Test
    func emptyFailedAndBrowserFailedResultsOfferRecovery() async {
        let actions = ImageInspectionActions(failsOpen: true)
        let empty = ImageInspectionViewModel(recognizer: ImageInspectionRecognizer(result: ImageRecognitionResult()),
                                             pasteboard: actions, urlOpener: actions)
        empty.analyze(Self.source, mode: .qr)
        await empty.waitForWorkForTesting()
        #expect(empty.canCopy == false && empty.statusMessage?.contains("No QR code") == true)
        let failed = ImageInspectionViewModel(recognizer: ImageInspectionRecognizer(fails: true), pasteboard: actions, urlOpener: actions)
        failed.analyze(Self.source, mode: .text)
        await failed.waitForWorkForTesting()
        #expect(failed.isWorking == false && failed.errorMessage != nil)
        let browser = ImageInspectionViewModel(
            recognizer: ImageInspectionRecognizer(result: ImageRecognitionResult(qrPayloads: ["https://example.invalid"])),
            pasteboard: actions, urlOpener: actions
        )
        browser.analyze(Self.source, mode: .qr)
        await browser.waitForWorkForTesting()
        browser.reviewSelectedLink()
        browser.openReviewedLink()
        await browser.waitForActionForTesting()
        #expect(browser.canCopy && browser.canReviewLink && browser.errorMessage != nil)
        #expect(browser.errorMessage?.contains("example.invalid") == false)
    }

    @Test
    func cancelledNonCooperativeRecognitionCannotRestorePrivateResults() async {
        let recognizer = DelayedImageInspectionRecognizer()
        let actions = ImageInspectionActions()
        let model = ImageInspectionViewModel(recognizer: recognizer, pasteboard: actions, urlOpener: actions)
        model.analyze(Self.source, mode: .text)
        await recognizer.waitUntilRequested()
        let pending = model.pendingWorkForTesting()
        model.stop()
        await recognizer.finish()
        await pending?.value
        #expect(model.result == nil && model.reviewedText.isEmpty && model.statusMessage == nil)
        #expect(await actions.copiedStrings().isEmpty)
        #expect(await actions.openedURLs().isEmpty)
    }

    @Test
    func switchingModesReusesExplicitSourceAndPreservesConversionSettings() async throws {
        let recognizer = ImageInspectionRecognizer(result: ImageRecognitionResult(text: "text", qrPayloads: ["QR payload"]))
        let actions = ImageInspectionActions()
        let inspection = ImageInspectionViewModel(recognizer: recognizer, pasteboard: actions, urlOpener: actions)
        let model = ImageToolsViewModel(converter: InspectionSourceLoader(), inspection: inspection, onGoBack: {})
        model.load(URL(fileURLWithPath: "/tmp/generated.png"))
        await model.waitForWorkForTesting()
        let source = try #require(model.source)
        model.format = .jpeg
        model.longestEdgeText = "800"
        model.mode = .text
        await inspection.waitForWorkForTesting()
        #expect(inspection.reviewedText == "text")
        #expect(model.source == source && model.canConvert == false)
        model.mode = .qr
        await inspection.waitForWorkForTesting()
        #expect(inspection.selectedPayload == "QR payload")
        model.mode = .convert
        #expect(inspection.result == nil && inspection.reviewedText.isEmpty)
        #expect(model.source == source && model.format == .jpeg && model.longestEdgeText == "800")
        #expect(model.canConvert)
        model.stop()
        #expect(model.source == nil)
    }

    private static var source: ImageConversionSource {
        ImageConversionSource(data: Data([1]), previewPNGData: Data([2]), filename: "generated.png", pixelWidth: 8, pixelHeight: 4)
    }
}

private actor ImageInspectionActions: PasteboardAccessing, URLOpening {
    private var copies: [String] = []
    private var opens: [URL] = []
    private var readCount = 0
    private let failsOpen: Bool
    init(failsOpen: Bool = false) { self.failsOpen = failsOpen }
    func readString() -> String? { readCount += 1; return nil }
    func writeString(_ string: String) { copies.append(string) }
    func openURL(_ url: URL) throws {
        if failsOpen { throw CocoaError(.fileReadNoPermission) }
        opens.append(url)
    }
    func copiedStrings() -> [String] { copies }
    func openedURLs() -> [URL] { opens }
    func reads() -> Int { readCount }
}

private actor ImageInspectionRecognizer: ImageRecognizing {
    let result: ImageRecognitionResult
    let fails: Bool
    init(result: ImageRecognitionResult = ImageRecognitionResult(), fails: Bool = false) { self.result = result; self.fails = fails }
    func recognize(_ source: ImageConversionSource, mode: ImageRecognitionMode) throws -> ImageRecognitionResult {
        if fails { throw ImageRecognitionError.recognitionFailed }
        return result
    }
}

private actor DelayedImageInspectionRecognizer: ImageRecognizing {
    private var continuation: CheckedContinuation<ImageRecognitionResult, Never>?
    private var requested: CheckedContinuation<Void, Never>?
    func recognize(_ source: ImageConversionSource, mode: ImageRecognitionMode) async -> ImageRecognitionResult {
        await withCheckedContinuation {
            continuation = $0
            requested?.resume()
            requested = nil
        }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func finish() { continuation?.resume(returning: ImageRecognitionResult(text: "late private text")); continuation = nil }
}

private actor InspectionSourceLoader: ImageConverting {
    func supportedFormats() -> [ImageConversionFormat] { [.png, .jpeg] }
    func loadImage(from url: URL) -> ImageConversionSource {
        ImageConversionSource(data: Data([1]), previewPNGData: Data([2]), filename: url.lastPathComponent, pixelWidth: 8, pixelHeight: 4)
    }
    func convert(_ source: ImageConversionSource, options: ImageConversionOptions) -> ImageConversionResult {
        ImageConversionResult(data: Data([1]), previewPNGData: Data([2]), format: options.format, pixelWidth: 8, pixelHeight: 4)
    }
}
