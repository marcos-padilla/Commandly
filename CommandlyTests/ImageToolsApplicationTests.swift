import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct ImageToolsApplicationTests {
    @Test @MainActor
    func chooseToolUsesExplicitPickerAndApplicationOwnsItsTools() throws {
        let converter = ImageToolsStubConverter()
        let registry = LauncherApplicationRegistry.makeBuiltIn(imageConversionService: converter)
        let application = try #require(registry.application(for: ImageToolsApplication.applicationID))
        #expect(application.definition.documentation != nil)
        #expect(application.definition.parentID == BuiltInLauncherApplicationGroup.catalogID)
        #expect(application.toolDefinitions.map(\.id) == [
            ImageToolsApplication.openToolID, ImageToolsApplication.chooseImageToolID,
            ImageToolsApplication.extractTextToolID, ImageToolsApplication.decodeQRToolID
        ])
        #expect(application.toolDefinitions.allSatisfy { $0.parentID == ImageToolsApplication.applicationID })
        #expect(registry.owningApplicationID(for: ImageToolsApplication.chooseImageToolID) == ImageToolsApplication.applicationID)
        #expect(registry.resolvedSettings(for: ImageToolsApplication.chooseImageToolID)?.isEnabled == true)
        #expect(registry.allManifests().contains { $0.id == ImageToolsApplication.chooseImageToolID && $0.keywords.contains("convert image") })
        guard case .present(let session) = application.launch(
            toolID: ImageToolsApplication.chooseImageToolID, arguments: CommandArguments(), in: makeContext()
        ) else { Issue.record("Expected image conversion session"); return }
        let model = try #require(session.model(as: ImageToolsViewModel.self))
        #expect(model.showsImageImporter)
        #expect(model.source == nil)
        session.stop()
        #expect(model.showsImageImporter == false)
    }

    @Test @MainActor
    func conversionsUseUserOptionsAndOnlyExplicitlyOfferExport() async throws {
        let converter = ImageToolsStubConverter()
        let model = ImageToolsViewModel(converter: converter, onGoBack: {})
        model.load(URL(fileURLWithPath: "/tmp/fixture.png"))
        await model.waitForWorkForTesting()
        #expect(model.result == nil)
        #expect(model.canConvert)
        model.format = .jpeg
        model.resizesImage = true
        model.longestEdgeText = "800"
        model.clockwiseQuarterTurns = 1
        model.convert()
        await model.waitForWorkForTesting()
        #expect(await converter.options() == ImageConversionOptions(format: .jpeg, longestEdge: 800, clockwiseQuarterTurns: 1))
        #expect(model.result?.format == .jpeg)
        #expect(model.suggestedFilename == "fixture-converted.jpg")
        #expect(model.showsFileExporter == false)
        model.perform(ImageToolsActionID.save)
        #expect(model.showsFileExporter)
        model.format = .png
        #expect(model.result == nil)
        #expect(model.showsFileExporter == false)
        #expect(model.footerActions.first?.id == ImageToolsActionID.convert)
    }

    @Test @MainActor
    func invalidDimensionsDoNotRunConverterAndExportFailureRemainsRecoverable() async {
        let converter = ImageToolsStubConverter()
        let model = ImageToolsViewModel(converter: converter, onGoBack: {})
        model.load(URL(fileURLWithPath: "/tmp/fixture.png"))
        await model.waitForWorkForTesting()
        model.resizesImage = true
        for invalid in ["", "0", "-1", "16385", "NaN", "1.5", "99999999999999999999"] {
            model.longestEdgeText = invalid
            #expect(model.canConvert == false)
            model.convert()
        }
        #expect(await converter.options() == nil)
        model.longestEdgeText = "1"
        model.convert()
        await model.waitForWorkForTesting()
        let completed = model.result
        model.exportCompleted(.failure(CocoaError(.fileWriteNoPermission)))
        #expect(model.result == completed)
        #expect(model.errorMessage?.contains("another location") == true)
        model.exportCompleted(.success(URL(fileURLWithPath: "/tmp/export.png")))
        #expect(model.errorMessage == nil)
        #expect(model.statusMessage == "Converted image saved.")
        model.stop()
        #expect(model.source == nil && model.result == nil)
    }

    @Test @MainActor
    func loadErrorPreservesRecoveryAndUnsafeFilenameIsSanitized() async {
        let failing = ImageToolsViewModel(converter: ImageToolsStubConverter(failsLoad: true), onGoBack: {})
        failing.load(URL(fileURLWithPath: "/tmp/not-image"))
        await failing.waitForWorkForTesting()
        #expect(failing.isWorking == false)
        #expect(failing.errorMessage?.contains("supported image") == true)
        #expect(failing.footerActions.first?.id == ImageToolsActionID.choose)
        let model = ImageToolsViewModel(converter: ImageToolsStubConverter(filename: "../bad:name\n.png"), onGoBack: {})
        model.load(URL(fileURLWithPath: "/tmp/fixture.png"))
        await model.waitForWorkForTesting()
        #expect(model.suggestedFilename.contains("/") == false)
        #expect(model.suggestedFilename.contains(":") == false)
        #expect(model.suggestedFilename.contains("\n") == false)
        #expect(model.suggestedFilename.hasPrefix(".") == false)
    }

    @Test @MainActor
    func cancelledNonCooperativeConversionCannotReplaceNewImage() async throws {
        let converter = ImageToolsDeferredConverter()
        let model = ImageToolsViewModel(converter: converter, onGoBack: {})
        model.load(URL(fileURLWithPath: "/tmp/first.png"))
        await model.waitForWorkForTesting()
        model.convert()
        await converter.waitUntilConverting()
        let pending = model.pendingWorkForTesting()
        #expect(model.handleEscape())
        #expect(model.isWorking == false)
        model.load(URL(fileURLWithPath: "/tmp/second.png"))
        await model.waitForWorkForTesting()
        await converter.finishConversion()
        // The retained task must finish before we inspect the model; no timing sleeps are used.
        await pending?.value
        #expect(model.source?.filename == "second.png")
        #expect(model.result == nil)
        model.stop()
        #expect(model.source == nil)
    }

    @MainActor
    private func makeContext() -> LauncherApplicationContext {
        LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:])
        )
    }
}

private actor ImageToolsStubConverter: ImageConverting {
    private var requested: ImageConversionOptions?
    private let failsLoad: Bool
    private let filename: String
    init(failsLoad: Bool = false, filename: String = "fixture.png") { self.failsLoad = failsLoad; self.filename = filename }
    func supportedFormats() -> [ImageConversionFormat] { [.png, .jpeg, .tiff] }
    func loadImage(from url: URL) throws -> ImageConversionSource {
        if failsLoad { throw ImageConversionError.invalidImage }
        return ImageConversionSource(data: Data([1]), previewPNGData: Data([2]), filename: filename, pixelWidth: 800, pixelHeight: 400)
    }
    func convert(_ source: ImageConversionSource, options: ImageConversionOptions) -> ImageConversionResult {
        requested = options
        return ImageConversionResult(data: Data([3]), previewPNGData: Data([4]), format: options.format, pixelWidth: 400, pixelHeight: 800)
    }
    func options() -> ImageConversionOptions? { requested }
}

private actor ImageToolsDeferredConverter: ImageConverting {
    private var conversion: CheckedContinuation<ImageConversionResult, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func supportedFormats() -> [ImageConversionFormat] { [.png] }
    func loadImage(from url: URL) -> ImageConversionSource {
        ImageConversionSource(data: Data([1]), previewPNGData: Data([2]), filename: url.lastPathComponent, pixelWidth: 2, pixelHeight: 1)
    }
    func convert(_ source: ImageConversionSource, options: ImageConversionOptions) async -> ImageConversionResult {
        let value = await withCheckedContinuation { continuation in
            conversion = continuation
            started?.resume()
            started = nil
        }
        return value
    }
    func waitUntilConverting() async {
        if conversion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishConversion() {
        conversion?.resume(returning: ImageConversionResult(data: Data([3]), previewPNGData: Data([4]), format: .png, pixelWidth: 2, pixelHeight: 1))
        conversion = nil
    }
}
