import Foundation

/// Text-only fragments for the reviewed provider protocols. Tool payloads are rejected, never run.
struct AITextStreamCodec {
    let providerID: AIProviderID
    private var text = ""
    private var textBytes = 0
    private var terminal = false
    private var finishReason: String?
    private var response: [String: AIJSONValue] = [:]
    private var eventCount = 0
    private var started = false

    init(providerID: AIProviderID) { self.providerID = providerID }

    mutating func consume(_ payload: String) throws -> String {
        eventCount += 1
        guard eventCount <= 32_768 else { throw AIProviderError.invalidProviderResponse }
        if payload == "[DONE]" {
            guard isChatCompatible, terminal == false, finishReason != nil else {
                throw AIProviderError.invalidProviderResponse
            }
            terminal = true
            return ""
        }
        guard terminal == false else { throw AIProviderError.invalidProviderResponse }
        guard let value = try? AIJSONValue(data: Data(payload.utf8)) else { throw AIProviderError.invalidProviderResponse }
        guard value.objectValue != nil else { throw AIProviderError.invalidProviderResponse }
        if (value["error"] != nil && value["error"] != .null) || value["type"]?.stringValue == "error" {
            throw AIProviderError.serviceUnavailable
        }
        let delta: String
        switch providerID {
        case .openAI: delta = try openAI(value)
        case .anthropic: delta = try anthropic(value)
        case .googleGemini: delta = try gemini(value)
        case .ollama: delta = try ollama(value)
        case .mistral, .groq, .xAI, .openRouter: delta = try chat(value)
        default: throw AIProviderError.unsupportedCapability
        }
        textBytes += delta.utf8.count
        guard textBytes <= 256 * 1_024 else { throw AIProviderError.invalidProviderResponse }
        text += delta
        return delta
    }

    func finalJSON() throws -> AIJSONValue {
        guard terminal, text.isEmpty == false else { throw AIProviderError.invalidProviderResponse }
        var root = response
        switch providerID {
        case .openAI:
            guard let output = root["output"]?.arrayValue else { throw AIProviderError.invalidProviderResponse }
            let finalText = output.filter { $0["type"]?.stringValue == "message" }.flatMap {
                $0["content"]?.arrayValue ?? []
            }.compactMap { item -> String? in
                item["type"]?.stringValue == "refusal" ? item["refusal"]?.stringValue : item["text"]?.stringValue
            }.joined()
            guard finalText == text else { throw AIProviderError.invalidProviderResponse }
        case .anthropic:
            root["content"] = .array([.object(["type": .string("text"), "text": .string(text)])])
            root["stop_reason"] = finishReason.map(AIJSONValue.string) ?? .null
        case .googleGemini:
            root["candidates"] = .array([.object([
                "content": .object(["role": .string("model"), "parts": .array([.object(["text": .string(text)])])]),
                "finishReason": finishReason.map(AIJSONValue.string) ?? .null
            ])])
        case .ollama:
            root["message"] = .object(["role": .string("assistant"), "content": .string(text)])
        default:
            root["choices"] = .array([.object([
                "index": .number(0), "message": .object(["role": .string("assistant"), "content": .string(text)]),
                "finish_reason": finishReason.map(AIJSONValue.string) ?? .null
            ])])
        }
        return .object(root)
    }

    private var isChatCompatible: Bool { [.mistral, .groq, .xAI, .openRouter].contains(providerID) }

    private mutating func openAI(_ value: AIJSONValue) throws -> String {
        guard let type = value["type"]?.stringValue else { throw AIProviderError.invalidProviderResponse }
        if type.contains("function_call") {
            throw AIProviderError.unsupportedCapability
        }
        if let itemType = value["item"]?["type"]?.stringValue,
           ["message", "reasoning"].contains(itemType) == false { throw AIProviderError.unsupportedCapability }
        switch type {
        case "response.output_text.delta", "response.refusal.delta":
            guard let delta = value["delta"]?.stringValue else { throw AIProviderError.invalidProviderResponse }
            return delta
        case "response.completed", "response.incomplete":
            guard let object = value["response"]?.objectValue,
                  object["error"] == nil || object["error"] == .null else { throw AIProviderError.invalidProviderResponse }
            if object["output"]?.arrayValue?.contains(where: {
                guard let type = $0["type"]?.stringValue else { return true }
                return ["message", "reasoning"].contains(type) == false
            }) == true {
                throw AIProviderError.unsupportedCapability
            }
            response = object
            terminal = true
        case "response.failed", "error": throw AIProviderError.serviceUnavailable
        default: break
        }
        return ""
    }

    private mutating func anthropic(_ value: AIJSONValue) throws -> String {
        switch value["type"]?.stringValue {
        case "message_start":
            guard started == false, let message = value["message"]?.objectValue else { throw AIProviderError.invalidProviderResponse }
            response = message
            started = true
        case "content_block_start":
            guard started else { throw AIProviderError.invalidProviderResponse }
            let block = value["content_block"]
            guard let type = block?["type"]?.stringValue else { throw AIProviderError.invalidProviderResponse }
            guard ["text", "thinking", "redacted_thinking"].contains(type) else { throw AIProviderError.unsupportedCapability }
            if type == "text" { return block?["text"]?.stringValue ?? "" }
        case "content_block_delta":
            guard started else { throw AIProviderError.invalidProviderResponse }
            if value["delta"]?["type"]?.stringValue == "input_json_delta" { throw AIProviderError.unsupportedCapability }
            if value["delta"]?["type"]?.stringValue == "text_delta" {
                guard let delta = value["delta"]?["text"]?.stringValue else { throw AIProviderError.invalidProviderResponse }
                return delta
            }
        case "message_delta":
            finishReason = value["delta"]?["stop_reason"]?.stringValue ?? finishReason
            if let usage = value["usage"]?.objectValue {
                response["usage"] = .object((response["usage"]?.objectValue ?? [:]).merging(usage) { _, new in new })
            }
        case "message_stop":
            guard started, finishReason != nil else { throw AIProviderError.invalidProviderResponse }
            terminal = true
        default: break
        }
        return ""
    }

    private mutating func chat(_ value: AIJSONValue) throws -> String {
        if let id = value["id"] { response["id"] = id }
        if let usage = value["usage"] { response["usage"] = usage }
        let choices = value["choices"]?.arrayValue ?? []
        guard choices.count <= 1 else { throw AIProviderError.unsupportedCapability }
        guard let choice = choices.first else { return "" }
        if let index = choice["index"]?.integerValue, index != 0 { throw AIProviderError.unsupportedCapability }
        let delta = choice["delta"]
        if delta?["function_call"] != nil || delta?["tool_calls"]?.arrayValue?.isEmpty == false {
            throw AIProviderError.unsupportedCapability
        }
        let content = try visibleText(delta?["content"])
        // OpenRouter repeats the terminal reason in a content-free usage frame.
        if let previous = finishReason {
            guard content.isEmpty else { throw AIProviderError.invalidProviderResponse }
            if let reason = choice["finish_reason"]?.stringValue, reason != previous {
                throw AIProviderError.invalidProviderResponse
            }
        }
        finishReason = choice["finish_reason"]?.stringValue ?? finishReason
        return content
    }

    private mutating func gemini(_ value: AIJSONValue) throws -> String {
        if let id = value["responseId"] { response["responseId"] = id }
        if let usage = value["usageMetadata"] { response["usageMetadata"] = usage }
        if value["promptFeedback"]?["blockReason"] != nil { throw AIProviderError.invalidProviderResponse }
        let candidates = value["candidates"]?.arrayValue ?? []
        guard candidates.count <= 1 else { throw AIProviderError.unsupportedCapability }
        guard let candidate = candidates.first else { return "" }
        let parts = candidate["content"]?["parts"]?.arrayValue ?? []
        var delta = ""
        for part in parts {
            if ["functionCall", "functionResponse", "executableCode", "codeExecutionResult", "inlineData", "fileData"]
                .contains(where: { part[$0] != nil }) { throw AIProviderError.unsupportedCapability }
            if part["thought"]?.booleanValue != true { delta += part["text"]?.stringValue ?? "" }
        }
        if let reason = candidate["finishReason"]?.stringValue {
            finishReason = reason
            terminal = true
        }
        return delta
    }

    private mutating func ollama(_ value: AIJSONValue) throws -> String {
        let message = value["message"]
        if message?["tool_calls"]?.arrayValue?.isEmpty == false { throw AIProviderError.unsupportedCapability }
        if value["done"]?.booleanValue == true {
            response = value.objectValue ?? [:]
            finishReason = value["done_reason"]?.stringValue
            guard finishReason != nil else { throw AIProviderError.invalidProviderResponse }
            terminal = true
        }
        return message?["content"]?.stringValue ?? ""
    }

    private func visibleText(_ value: AIJSONValue?) throws -> String {
        guard let value, value != .null else { return "" }
        if let string = value.stringValue { return string }
        guard let array = value.arrayValue else { throw AIProviderError.invalidProviderResponse }
        return array.compactMap { part in
            part["type"]?.stringValue == "text" ? part["text"]?.stringValue : nil
        }.joined()
    }
}
