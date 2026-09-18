#if DEBUG
import AIKit
import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

@Suite("Generated Finder image conversation", .timeLimit(.minutes(1)))
@MainActor
struct FinderAIImageDebugFixtureTests {
    @Test
    func realConversationPausesForExactApprovalThenVerifiesActualJPEG() async throws {
        let fixture = FinderAIImageDebugFixture()
        defer { try? FileManager.default.removeItem(at: fixture.files.directory) }
        #expect(!FileManager.default.fileExists(atPath: fixture.files.directory.path))
        let model = makeModel(fixture)
        defer { model.stop() }
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.providerLabel?.contains("Generated Local Fixture") == true)
        let source = try Data(contentsOf: fixture.files.source)
        model.draft = FinderAIImageDebugFixture.prompt
        model.send()
        try await waitForResponse(model)
        let approval = try #require(model.pendingApproval)
        guard case .mutation(let call, let plan) = approval else { Issue.record("A real mutation approval is required"); return }
        #expect(call.name == "finder_convert_image")
        let operation = try #require(plan.operations.first)
        #expect(plan.operations.count == 1)
        #expect(operation.kind == .convertImage)
        #expect(operation.imageConversion == ImageConversionOptions(format: .jpeg, longestEdge: 320, clockwiseQuarterTurns: 1))
        #expect(operation.resultingNames == ["generated-converted.jpg"])
        #expect(operation.sourceNames.joined().contains("generated-source.png"))
        #expect(operation.destinationDescription?.contains("Output") == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.files.output.path))
        #expect(await fixture.runtime.completionCount == 3)
        model.approvePendingRequest()
        try await waitForResponse(model)
        #expect(model.phase == .ready && model.pendingApproval == nil)
        #expect(model.entries.contains { $0.role == .assistant && $0.text.contains("native image tool completed") })
        #expect(await fixture.runtime.completionCount == 4)
        let output = try Data(contentsOf: fixture.files.output)
        let image = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        #expect(CGImageSourceGetType(image) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 180)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 320)
        #expect(try Data(contentsOf: fixture.files.source) == source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.output.deletingLastPathComponent().path) == ["generated-converted.jpg"])
        let replay = await fixture.services.toolExecutor.executeApproved(approval, in: plan.sessionID)
        #expect(replay.isError)
        #expect(try Data(contentsOf: fixture.files.output) == output)
    }

    @Test
    func denialAndUnknownPromptNeverWriteAConversionAndFreshTurnCanRetry() async throws {
        let fixture = FinderAIImageDebugFixture()
        defer { try? FileManager.default.removeItem(at: fixture.files.directory) }
        let model = makeModel(fixture)
        defer { model.stop() }
        await model.start()
        model.draft = "Read my real private files"
        model.send()
        try await waitForResponse(model)
        #expect(model.pendingApproval == nil && model.phase == .ready)
        #expect(await fixture.runtime.completionCount == 0)
        #expect(model.entries.contains { $0.text.contains("no model or network") })
        model.draft = FinderAIImageDebugFixture.prompt
        model.send()
        try await waitForResponse(model)
        #expect(model.phase == .awaitingApproval)
        model.denyPendingRequest()
        try await waitForResponse(model)
        #expect(model.entries.contains { $0.text.contains("you denied the conversion") })
        #expect(!FileManager.default.fileExists(atPath: fixture.files.output.path))
        model.draft = FinderAIImageDebugFixture.prompt
        model.send()
        try await waitForResponse(model)
        #expect(model.pendingApproval != nil)
        model.approvePendingRequest()
        try await waitForResponse(model)
        #expect(FileManager.default.fileExists(atPath: fixture.files.output.path))
    }

    @Test
    func leavingDuringApprovalPreventsWritingAndEachFixtureAuthorizesOnlyItsGeneratedRoot() async throws {
        let fixture = FinderAIImageDebugFixture()
        let other = FinderAIImageDebugFixture()
        defer { try? FileManager.default.removeItem(at: fixture.files.directory); try? FileManager.default.removeItem(at: other.files.directory) }
        #expect(fixture.files.directory != other.files.directory)
        let model = makeModel(fixture)
        await model.start()
        let session = await fixture.services.workspace.beginSession()
        defer { Task { await fixture.services.workspace.endSession(session) } }
        let roots = try await fixture.services.workspace.authorizedRoots(in: session)
        #expect(roots.count == 1)
        #expect(roots.first?.displayName == fixture.files.directory.lastPathComponent)
        #expect(!FileManager.default.fileExists(atPath: other.files.directory.path))
        model.draft = FinderAIImageDebugFixture.prompt
        model.send()
        try await waitForResponse(model)
        #expect(model.phase == .awaitingApproval)
        model.stop()
        #expect(model.pendingApproval == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.files.output.path))
    }

    @Test
    func existingOutputProducesHonestFailureAndWrongProviderCannotDriveScript() async throws {
        let fixture = FinderAIImageDebugFixture()
        defer { try? FileManager.default.removeItem(at: fixture.files.directory) }
        let model = makeModel(fixture)
        defer { model.stop() }
        await model.start()
        let previous = Data("generated preexisting output".utf8)
        try previous.write(to: fixture.files.output)
        model.draft = FinderAIImageDebugFixture.prompt
        model.send()
        try await waitForResponse(model)
        #expect(model.phase == .ready && model.pendingApproval == nil)
        #expect(!model.entries.contains { $0.text.contains("native image tool completed") })
        #expect(model.entries.contains { $0.text.contains("did not complete") })
        #expect(try Data(contentsOf: fixture.files.output) == previous)
        let selection = try #require(try await fixture.runtime.activeSelection())
        await #expect(throws: AIProviderRuntimeError.connectionMismatch) {
            try await fixture.runtime.complete(AICompletionRequest(modelID: selection.modelID,
                messages: [.user(FinderAIImageDebugFixture.prompt)]), providerID: "real-provider",
                connectionRevision: selection.connectionRevision)
        }
    }

    private func makeModel(_ fixture: FinderAIImageDebugFixture) -> FinderAIViewModel {
        FinderAIViewModel(runtime: fixture.services.runtime, workspace: fixture.services.workspace,
            toolExecutor: fixture.services.toolExecutor, onGoBack: {}, onOpenSettings: {})
    }

    private func waitForResponse(_ model: FinderAIViewModel) async throws {
        // Yield until the real model publishes approval or completion; the suite deadline cancels
        // the loop on a regression. No fixed sleeps or assumed codec completion time are used.
        while model.phase == .responding { try Task.checkCancellation(); await Task.yield() }
    }
}
#endif
