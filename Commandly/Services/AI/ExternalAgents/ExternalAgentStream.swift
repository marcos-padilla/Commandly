import AIKit
import Foundation

/// Bounded SSE framing. Tool progress never becomes assistant content or executable client data.
actor ExternalAgentStream {
    private var event = ""
    private var data: [String] = []
    private var eventBytes = 0
    private var textBytes = 0
    private var finished = false
    private var done = false
    private var hasText = false
    private let onText: ExternalAgentTextReceiver
    private let onProgress: ExternalAgentProgressReceiver
    init(onText: @escaping ExternalAgentTextReceiver, onProgress: @escaping ExternalAgentProgressReceiver) {
        self.onText = onText; self.onProgress = onProgress
    }
    func accept(_ line: String) async throws {
        try Task.checkCancellation()
        guard line.utf8.count <= 512 * 1024 else { throw ExternalAgentError.tooLarge }
        if line.isEmpty { try await flush(); return }
        if line.hasPrefix(":") { return }
        if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); return }
        if line.hasPrefix("data:") {
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            eventBytes += payload.utf8.count
            guard eventBytes <= 512 * 1024 else { throw ExternalAgentError.tooLarge }
            data.append(payload)
        }
    }
    func complete() async throws {
        try await flush()
        guard done, finished, hasText else { throw ExternalAgentError.invalidResponse }
    }
    private func flush() async throws {
        guard !data.isEmpty else { event = ""; return }
        let payload = data.joined(separator: "\n")
        let eventName = event
        data = []; event = ""; eventBytes = 0
        guard !done else { throw ExternalAgentError.invalidResponse }
        if payload == "[DONE]" { done = true; return }
        guard let object = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any], object["error"] == nil else {
            throw ExternalAgentError.invalidResponse
        }
        if eventName == "hermes.tool.progress" { try await onProgress(); return }
        if eventName.contains("approval") { throw ExternalAgentError.unsupportedTool }
        guard eventName.isEmpty || eventName == "message" || eventName == "chat.completion.chunk",
              let choices = object["choices"] as? [[String: Any]] else { throw ExternalAgentError.invalidResponse }
        for choice in choices {
            guard (choice["index"] as? Int) == 0 else { continue }
            if let delta = choice["delta"] as? [String: Any] {
                if delta["tool_calls"] != nil || delta["function_call"] != nil { throw ExternalAgentError.unsupportedTool }
                if let text = delta["content"] as? String, !text.isEmpty {
                    guard !finished else { throw ExternalAgentError.invalidResponse }
                    textBytes += text.utf8.count
                    guard textBytes <= 512 * 1024 else { throw ExternalAgentError.tooLarge }
                    hasText = true; try await onText(text)
                }
            }
            if let reason = choice["finish_reason"] as? String {
                if reason == "tool_calls" || reason == "function_call" { throw ExternalAgentError.unsupportedTool }
                guard reason == "stop" else { throw ExternalAgentError.invalidResponse }
                finished = true
            }
        }
    }
}
