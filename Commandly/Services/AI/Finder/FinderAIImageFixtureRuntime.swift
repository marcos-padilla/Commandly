#if DEBUG
import AIKit
import Foundation

/// A bounded local script, visibly identified as generated; never a network/provider substitute.
/// It uses actual prior tool results for opaque handles and cannot issue or execute an approval.
actor FinderAIImageFixtureRuntime: AIProviderRuntimeServicing {
    private let files: FinderAIImageFixtureFiles
    private let selection = AIActiveProviderSelection(providerID: "generated-local-fixture",
        providerName: "Generated Local Fixture", modelID: "image-conversion-script",
        modelName: "Image Conversion Script", supportsTools: true, connectionRevision: UUID().uuidString)
    private(set) var completionCount = 0

    init(files: FinderAIImageFixtureFiles) { self.files = files }

    func activeSelection() async throws -> AIActiveProviderSelection? {
        try Task.checkCancellation()
        try await files.prepare()
        try Task.checkCancellation()
        return selection
    }

    func complete(_ request: AICompletionRequest, providerID: String, connectionRevision: String) async throws -> AICompletionResponse {
        try Task.checkCancellation()
        guard providerID == selection.providerID, connectionRevision == selection.connectionRevision else {
            throw AIProviderRuntimeError.connectionMismatch
        }
        guard request.modelID == selection.modelID else { throw AIProviderRuntimeError.modelMismatch }
        guard request.messages.count <= 64, let userIndex = request.messages.lastIndex(where: { $0.role == .user }),
              request.messages[userIndex].content == [.text(FinderAIImageDebugFixture.prompt)] else {
            return final("Generated local demo — no model or network is running. Enter this exact request: “\(FinderAIImageDebugFixture.prompt)” No conversion was requested by this reply.")
        }
        completionCount += 1
        let tail = request.messages.dropFirst(userIndex + 1)
        let results = tail.flatMap(\.toolResults)
        guard results.count <= 3, tail.count <= 6 else { throw FinderAIImageFixtureError.invalidTranscript }
        let names = ["finder_list_roots", "finder_list_directory", "finder_convert_image"]
        let suffix = String(request.messages.prefix(userIndex + 1).count { $0.role == .user })
        for (index, result) in results.enumerated() {
            guard result.toolName == names[index], result.callID == "generated-\(index)-\(suffix)" else {
                throw FinderAIImageFixtureError.invalidTranscript
            }
            if result.isError {
                if case let .object(content) = result.content,
                   case let .object(error)? = content["error"], error["code"] == .string("user_denied") {
                    return final("Generated local demo: you denied the conversion. No conversion approval was issued.")
                }
                return final("Generated local demo: the local tool did not complete the conversion. Review the activity above. The script does not report success without a completed tool result.")
            }
        }
        switch results.count {
        case 0:
            return call(names[0], id: "generated-0-\(suffix)", arguments: .object([:]),
                text: "Generated local demo. I will list only the generated workspace, then propose a real native conversion for your approval.")
        case 1:
            guard case let .object(content) = results[0].content, case let .array(roots)? = content["roots"], roots.count == 1,
                  case let .object(root) = roots[0], let identifier = uuid(root["id"]) else {
                throw FinderAIImageFixtureError.invalidTranscript
            }
            return call(names[1], id: "generated-1-\(suffix)", arguments: .object([
                "directory_type": .string("root"), "directory_id": .string(identifier), "limit": .number(10)
            ]))
        case 2:
            guard case let .object(content) = results[1].content, case let .array(items)? = content["items"], items.count <= 10,
                  let source = itemID(named: "generated-source.png", kind: "file", items: items),
                  let output = itemID(named: "Output", kind: "directory", items: items) else {
                throw FinderAIImageFixtureError.invalidTranscript
            }
            return call(names[2], id: "generated-2-\(suffix)", arguments: .object([
                "item_id": .string(source), "destination_type": .string("item"), "destination_id": .string(output),
                "output_name": .string("generated-converted.jpg"), "format": .string("jpeg"),
                "longest_edge": .number(320), "clockwise_quarter_turns": .number(1)
            ]), text: "Generated local demo: review the exact JPEG, 320-pixel longest edge, and clockwise rotation below. The real converter runs only after Approve Once.")
        case 3:
            guard case let .object(content) = results[2].content, content["status"] == .string("completed"),
                  content["completed_count"] == .number(1), case let .array(items)? = content["results"], items.count == 1,
                  case let .object(item) = items[0], item["status"] == .string("completed"),
                  item["resulting_name"] == .string("generated-converted.jpg") else {
                return final("Generated local demo: the tool did not confirm a completed conversion. Review the activity above.")
            }
            return final("Generated local demo: the native image tool completed generated-converted.jpg in Output. The generated source is unchanged. This is a scripted reply based on the actual local tool result; no provider or network ran.")
        default: throw FinderAIImageFixtureError.invalidTranscript
        }
    }

    private func call(_ name: String, id: String, arguments: AIJSONValue, text: String? = nil) -> AICompletionResponse {
        AICompletionResponse(id: id, message: .assistant(text, toolCalls: [AIToolCall(id: id, name: name, arguments: arguments)]),
                             finishReason: .toolCalls)
    }

    private func final(_ text: String) -> AICompletionResponse {
        AICompletionResponse(id: "generated-terminal", message: .assistant(text), finishReason: .completed)
    }

    private func uuid(_ value: AIJSONValue?) -> String? {
        guard case let .string(identifier)? = value, UUID(uuidString: identifier) != nil else { return nil }
        return identifier
    }

    private func itemID(named name: String, kind: String, items: [AIJSONValue]) -> String? {
        let matches = items.compactMap { item -> String? in
            guard case let .object(value) = item, value["name"] == .string(name), value["kind"] == .string(kind) else { return nil }
            return uuid(value["id"])
        }
        return matches.count == 1 ? matches.first : nil
    }
}
#endif
