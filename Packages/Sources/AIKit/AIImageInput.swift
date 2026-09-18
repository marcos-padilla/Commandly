import Foundation

/// One locally prepared image, never a URL or provider upload handle. Not Codable; debug output is redacted.
public struct AIImageInput: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mediaType: String
    public init(jpegData: Data, pixelWidth: Int, pixelHeight: Int) throws {
        guard !jpegData.isEmpty, jpegData.count <= 2 * 1_024 * 1_024,
              jpegData.starts(with: [0xff, 0xd8, 0xff]),
              (1...2_048).contains(pixelWidth), (1...2_048).contains(pixelHeight) else { throw AIProviderError.invalidRequest }
        self.data = jpegData; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; mediaType = "image/jpeg"
    }
    public var description: String { "AIImageInput(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["data": "<redacted>"], displayStyle: .struct) }
    /// Explicit curated image-capable families supported by the three implemented request codecs.
    /// Unknown/specialized models remain unavailable until reviewed; this performs no discovery request.
    public static func supports(providerID: AIProviderID, modelID: String) -> Bool {
        let model = modelID.lowercased()
        let excluded = ["audio", "realtime", "image", "embedding", "transcribe", "tts", "codex", "search", "computer-use"]
        guard !excluded.contains(where: model.contains) else { return false }
        switch providerID {
        case .openAI:
            let roots = ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5.1", "gpt-5.2", "gpt-6-astra"]
            return roots.contains { root in
                if model == root { return true }
                let suffix = model.dropFirst(root.count)
                return model.hasPrefix(root) && suffix.count == 11 && suffix.first == "-" && suffix.dropFirst().allSatisfy { $0.isNumber || $0 == "-" }
            }
        case .anthropic:
            return ["claude-3-", "claude-3.5-", "claude-3-5-", "claude-3-7-", "claude-sonnet-4", "claude-opus-4", "claude-opus-5", "claude-haiku-4"].contains(where: model.hasPrefix)
        case .googleGemini:
            return ["models/gemini-1.5-", "models/gemini-2.", "models/gemini-3"].contains(where: model.hasPrefix)
        default: return false
        }
    }
}

extension AICompletionRequest {
    /// Insert the one explicitly reviewed attachment into the only user message. Text-only bodies are byte unchanged.
    func attachingImage(to body: AIJSONValue, providerID: AIProviderID) throws -> AIJSONValue {
        guard let imageInput else { return body }
        guard var root = body.objectValue else { throw AIProviderError.invalidRequest }
        let key = providerID == .openAI ? "input" : providerID == .anthropic ? "messages" : "contents"
        let partsKey = providerID == .googleGemini ? "parts" : "content"
        guard var messages = root[key]?.arrayValue,
              let index = messages.lastIndex(where: { $0["role"]?.stringValue == "user" }),
              var message = messages[index].objectValue else { throw AIProviderError.invalidRequest }
        var parts: [AIJSONValue]
        if providerID == .openAI, let text = message[partsKey]?.stringValue {
            parts = [.object(["type": .string("input_text"), "text": .string(text)])]
        } else if let existing = message[partsKey]?.arrayValue { parts = existing }
        else { throw AIProviderError.invalidRequest }
        let encoded = imageInput.data.base64EncodedString()
        let part: AIJSONValue
        switch providerID {
        case .openAI:
            part = .object(["type": .string("input_image"), "image_url": .string("data:image/jpeg;base64," + encoded), "detail": .string("auto")])
        case .anthropic:
            part = .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string(imageInput.mediaType), "data": .string(encoded)])])
        case .googleGemini:
            part = .object(["inlineData": .object(["mimeType": .string(imageInput.mediaType), "data": .string(encoded)])])
        default: throw AIProviderError.invalidRequest
        }
        parts.insert(part, at: 0); message[partsKey] = .array(parts); messages[index] = .object(message); root[key] = .array(messages)
        return .object(root)
    }
}
