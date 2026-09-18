import AIKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

private func generatedScreenshot() throws -> ScreenshotImage {
    let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    let data = try #require(Data(base64Encoded: encoded))
    return try .init(pngData: data, previewPNGData: data, kind: .display, pixelWidth: 1, pixelHeight: 1)
}
private actor PayloadRecorder: AIHTTPTransport {
    var bodies: [Data] = []
    func send(_ request: AIHTTPRequest) throws -> AIHTTPResponse {
        bodies.append(request.body ?? Data())
        throw AIProviderError.networkUnavailable
    }
    func body() -> Data? { bodies.first }
}
@Suite struct VisualAIWireTests {
    @Test(arguments: [AIProviderID.openAI, .anthropic, .googleGemini])
    func realAdaptersEncodeExactReviewedImage(provider: AIProviderID) async throws {
        let recorder = PayloadRecorder()
        let registry = try AIProviderRegistry.standard(transport: recorder)
        let image = try await VisualAIImagePreparer().prepare(generatedScreenshot())
        let model: String = provider == .openAI ? "gpt-4o" : provider == .anthropic ? "claude-sonnet-4-20250514" : "models/gemini-2.5-flash"
        do {
            _ = try await registry.adapter(for: provider).complete(request: .init(modelID: model, messages: [.user("Question")], toolChoice: .none, imageInput: image), configuration: .init(providerID: provider, credential: AICredential("generated-test-credential")))
            Issue.record("Recording transport must not return a real completion")
        } catch let error as AIProviderError { #expect(error == .networkUnavailable) }
        catch { Issue.record("Unexpected generated transport error") }
        let root = try AIJSONValue(data: #require(await recorder.body()))
        let encoded = image.data.base64EncodedString()
        if provider == .openAI { #expect(root["input"]?.arrayValue?.last?["content"]?.arrayValue?.first?["image_url"]?.stringValue == "data:image/jpeg;base64," + encoded) }
        else if provider == .anthropic { #expect(root["messages"]?.arrayValue?.last?["content"]?.arrayValue?.first?["source"]?["data"]?.stringValue == encoded) }
        else { #expect(root["contents"]?.arrayValue?.last?["parts"]?.arrayValue?.first?["inlineData"]?["data"]?.stringValue == encoded) }
    }
    @Test func unsupportedAndStatefulImageRequestsFailClosed() async throws {
        let image = try await VisualAIImagePreparer().prepare(generatedScreenshot())
        #expect(image.pixelWidth == 1 && image.pixelHeight == 1)
        #expect(image.data.count <= 2 * 1_024 * 1_024)
        #expect(throws: AIProviderError.self) { try AICompletionRequest(modelID: "unknown", messages: [.user("Q")], toolChoice: .none, imageInput: image).validate(for: .openAI) }
        #expect(throws: AIProviderError.self) { try AICompletionRequest(modelID: "gpt-4o", messages: [.user("Q"), .assistant("A"), .user("Q2")], toolChoice: .none, imageInput: image).validate(for: .openAI) }
        #expect(!String(reflecting: image).contains(image.data.base64EncodedString()))
    }
}
private actor GeneratedAI: VisualAIServicing {
    let choice = VisualAISelection(connection: .init(providerID: "openai", modelID: "gpt-4o", modelDisplayName: "Generated Vision", connectionRevision: "fixture"), providerName: "Generated Provider")
    private(set) var sent: AIImageInput?
    func selections() -> [VisualAISelection] { [choice] }
    func respond(prompt: String, image: AIImageInput, selection: VisualAISelection) -> String { sent = image; return "Generated answer" }
}
@MainActor private final class GeneratedCapture: ScreenshotCapturing {
    var count = 0
    func capture(_ request: ScreenshotRequest) throws -> ScreenshotImage { count += 1; return try generatedScreenshot() }
    func cancel() {}
}
private struct NoCopy: ScreenshotCopying { func copyPNG(_ data: Data) async throws {} }
@Suite @MainActor struct VisualAIModelTests {
    @Test func capturePreviewRemoveAndSendAreSeparateExplicitActions() async throws {
        let capture = GeneratedCapture(); let ai = GeneratedAI()
        let screenshots = ScreenshotApplicationServices(permissions: InMemoryPermissionService(), makeCapture: { capture }, copier: NoCopy(), privacySettings: InMemoryPrivacySettingsOpener())
        let model = VisualAIModel(services: .init(screenshots: screenshots, imagePreparer: VisualAIImagePreparer(), ai: ai), openAISettings: {}, goBack: {})
        model.loadModels(); await model.waitForCatalogForTesting()
        #expect(capture.count == 0); #expect(await ai.sent == nil)
        model.capture(); await model.waitForWorkForTesting()
        let preview = try #require(model.image)
        #expect(capture.count == 1); #expect(await ai.sent == nil)
        model.clearImage(); model.send(); #expect(await ai.sent == nil)
        model.capture(); await model.waitForWorkForTesting(); model.send(); await model.waitForWorkForTesting()
        #expect(await ai.sent == model.image); #expect(model.image == preview); #expect(model.response == "Generated answer")
        model.stop(); #expect(model.image == nil && model.response.isEmpty && model.prompt.isEmpty)
    }
}
