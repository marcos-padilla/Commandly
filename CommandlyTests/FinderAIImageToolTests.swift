import AIKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Finder AI image conversion tool", .timeLimit(.minutes(1)))
struct FinderAIImageToolTests {
    @Test
    func typedToolRequiresExactLocalApprovalBeforeRealConversionAndReturnsOnlyMetadata() async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let service = await files.service()
        let handles = try await files.handles(service)
        let executor = FinderAIToolExecutor(workspace: service, approvalCoordinator: service)
        let definition = try #require(executor.definitions.first { $0.name == "finder_convert_image" })
        #expect(definition.effect == .mutating && definition.confirmation == .always)
        let call = Self.call(handles)
        let outcome = await executor.execute(call, in: handles.session)
        guard case .requiresApproval(let approval) = outcome,
              case .mutation(_, let plan) = approval else { Issue.record("Conversion must pause on a local mutation plan"); return }
        #expect(approval.confirmationTitle == "Convert Image?")
        #expect(plan.operations.first?.imageConversion == .init(format: .png, longestEdge: 8, clockwiseQuarterTurns: 1))
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path).isEmpty)
        let denied = executor.denied(approval)
        #expect(denied.isError)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path).isEmpty)
        let result = await executor.executeApproved(approval, in: handles.session)
        #expect(!result.isError && result.callID == call.id && result.toolName == call.name)
        #expect(result.content.objectValue?["status"]?.stringValue == "completed")
        let serialized = try JSONEncoder().encode(result)
        let json = String(decoding: serialized, as: UTF8.self)
        #expect(!json.contains(files.base.path) && !json.contains("PRIVATE GENERATED") && !json.contains(files.sourceData.base64EncodedString()))
        #expect(FileManager.default.fileExists(atPath: files.destination.appendingPathComponent("converted.png").path))
        let replay = await executor.executeApproved(approval, in: handles.session)
        #expect(replay.isError)
    }

    @Test
    func modelCannotSupplyPathsURLsExtraCapabilitiesOrMalformedOptions() async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let converter = try FinderAIImageGatedConverter()
        let service = await files.service(converter: converter)
        let handles = try await files.handles(service)
        let executor = FinderAIToolExecutor(workspace: service, approvalCoordinator: service)
        let base = try #require(Self.call(handles).arguments.objectValue)
        let changes: [[String: AIJSONValue]] = [
            ["source_url": .string("https://example.com/private.png")],
            ["item_id": .string(files.source.path)],
            ["output_name": .string("../escape.png")],
            ["clockwise_quarter_turns": .number(0.5)],
            ["longest_edge": .number(16_385)],
            ["format": .string("shell")],
            ["overwrite": .boolean(true)]
        ]
        for change in changes {
            let arguments = base.merging(change) { _, next in next }
            let outcome = await executor.execute(AIToolCall(id: UUID().uuidString, name: "finder_convert_image", arguments: .object(arguments)), in: handles.session)
            guard case .completed(let result) = outcome else { Issue.record("Malformed conversion arguments must not reach approval"); continue }
            #expect(result.isError)
            let text = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
            #expect(!text.contains(files.source.path) && !text.contains("https://example.com"))
        }
        #expect(await converter.calls == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path).isEmpty)
    }

    private static func call(_ handles: FinderAIImageHandles) -> AIToolCall {
        AIToolCall(id: UUID().uuidString, name: "finder_convert_image", arguments: .object([
            "item_id": .string(handles.source.rawValue.uuidString),
            "destination_type": .string("item"),
            "destination_id": .string(handles.destination.rawValue.uuidString),
            "output_name": .string("converted.png"), "format": .string("png"),
            "longest_edge": .number(8), "clockwise_quarter_turns": .number(1)
        ]))
    }
}
