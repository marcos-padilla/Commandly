import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct ColorSearchModelTests {
    @Test func sameParserRecognizesOnlyCompleteBoundedQueries() throws {
        let provider = ColorSearchProvider()
        for input in ["#966A5E", "rgb(30% 40 50 / 25%)", "hsl(120, 100%, 50%)"] {
            #expect(provider.color(for: input) == CommandlyColor(string: input))
        }
        for input in ["open #966A5E", "rgb(1 2)", "convert red", String(repeating: "x", count: 100_000)] {
            #expect(provider.color(for: input) == nil)
        }
    }

    @Test func sixTypedActionsCopyTheirActualValues() async throws {
        let board = ColorTestPasteboard()
        let model = ColorSearchModel(pasteboard: board)
        model.update(query: "#966A5E80")
        let result = try #require(model.result)
        #expect(model.selectedFormat == .hexWithAlpha)
        #expect(model.actions.map(\.id) == CommandlyColorFormat.allCases.map(\.copyActionID))
        for format in CommandlyColorFormat.allCases {
            model.presentActions(resultID: result.id)
            model.perform(format.copyActionID, resultID: result.id)
            await model.flushCopyForTesting()
            #expect(await board.last == result.color.formatted(format))
            #expect(model.selectedFormat == format)
            #expect(model.showsActions == false)
            #expect(model.statusMessage == "\(format.title) copied.")
        }
    }

    @Test func editsAndRepeatedQueryRejectOldActionsAndQueuedWrites() async throws {
        let board = ColorTestPasteboard()
        let model = ColorSearchModel(pasteboard: board)
        model.update(query: "#1234")
        let first = try #require(model.result)
        model.copy(resultID: first.id)
        let queuedCopy = model.pendingCopyForTesting()
        model.update(query: "#1234")
        let second = try #require(model.result)
        #expect(first.id != second.id)
        model.perform(CommandlyColorFormat.hsl.copyActionID, resultID: first.id)
        model.presentActions(resultID: first.id)
        await queuedCopy?.value
        #expect(await board.last == nil)
        #expect(model.showsActions == false)
        model.update(query: "invalid")
        model.copy(resultID: second.id)
        #expect(model.result == nil)
        #expect(model.actions.allSatisfy { !$0.isEnabled })
    }

    @Test func inFlightCopyCannotOverwriteNewQueryStatus() async throws {
        let board = ColorTestPasteboard(holdsWrites: true)
        let model = ColorSearchModel(pasteboard: board)
        model.update(query: "#F00")
        let result = try #require(model.result)
        model.copy(resultID: result.id)
        let pendingCopy = model.pendingCopyForTesting()
        await board.waitForWrite()
        model.update(query: "#0F0")
        await board.release()
        await pendingCopy?.value
        #expect(model.result?.color.hex == "#00FF00")
        #expect(model.statusMessage == nil)
        // The authorized write was dispatched before the edit. We do not claim to revoke it.
        #expect(await board.last == "#FF0000")
    }

    @Test func stopCancelsQueuedCopyAndDiscardsDraft() async throws {
        let board = ColorTestPasteboard()
        let model = ColorSearchModel(pasteboard: board)
        model.update(query: "#F00")
        let result = try #require(model.result)
        model.presentActions(resultID: result.id)
        model.actionsQuery = "HSL"
        model.copy(resultID: result.id)
        let pendingCopy = model.pendingCopyForTesting()
        model.stop()
        await pendingCopy?.value
        #expect(model.result == nil)
        #expect(model.actionsQuery.isEmpty)
        #expect(!model.showsActions)
        #expect(await board.last == nil)
    }

    @Test func editorUsesSameSixFormatsAndTransparentReturnDefault() async throws {
        let board = ColorTestPasteboard()
        let model = OfflineToolsViewModel(tool: .color, services: fixtureServices(board: board), onGoBack: {})
        model.colorInput = "hsl(120 100% 50% / 25%)"
        let color = try #require(model.parsedColor)
        #expect(model.selectedColorFormat == .hexWithAlpha)
        #expect(model.menuActions.prefix(6).map(\.id) == CommandlyColorFormat.allCases.map(\.copyActionID))
        model.perform(BuiltInCommandActionID.copy)
        await model.flushCopyForTesting()
        #expect(await board.last == "#00FF0040")
        for format in CommandlyColorFormat.allCases {
            model.perform(format.copyActionID)
            await model.flushCopyForTesting()
            #expect(await board.last == color.formatted(format))
            #expect(model.footerActions.first?.title == "Copy \(format.title)")
        }
        model.colorInput = "rgbbad(1,2,3)"
        #expect(model.footerActions.first?.isEnabled == false)
        #expect(model.menuActions.prefix(6).allSatisfy { !$0.isEnabled })
    }

    @Test func editingWhileSamplerOpenPreservesNewInput() async {
        let sampler = ColorTestSampler()
        let model = OfflineToolsViewModel(tool: .color, services: fixtureServices(board: ColorTestPasteboard(), sampler: sampler), onGoBack: {})
        model.sampleColor()
        await sampler.waitForStart()
        model.colorInput = "#123456"
        sampler.finish(CommandlyColor(string: "#F00"))
        await model.flushSamplingForTesting()
        #expect(model.colorInput == "#123456")
        #expect(model.statusMessage == nil)
    }

    @Test func returningToSameTextStillRejectsEarlierSamplerResult() async {
        let sampler = ColorTestSampler()
        let model = OfflineToolsViewModel(tool: .color, services: fixtureServices(board: ColorTestPasteboard(), sampler: sampler), onGoBack: {})
        let original = model.colorInput
        model.sampleColor()
        await sampler.waitForStart()
        model.colorInput = "#000000"
        model.colorInput = original
        sampler.finish(CommandlyColor(string: "#F00"))
        await model.flushSamplingForTesting()
        #expect(model.colorInput == original)
        #expect(model.statusMessage == nil)
    }

    private func fixtureServices(board: ColorTestPasteboard, sampler: ColorTestSampler = ColorTestSampler()) -> OfflineToolsServices {
        OfflineToolsServices(pasteboard: board, dictionary: ColorTestDictionary(), colorSampler: sampler, fontCatalog: ColorTestFonts())
    }
}

private actor ColorTestPasteboard: PasteboardAccessing {
    private(set) var last: String?
    let holdsWrites: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var started: CheckedContinuation<Void, Never>?
    init(holdsWrites: Bool = false) { self.holdsWrites = holdsWrites }
    func readString() async -> String? { nil }
    func writeString(_ string: String) async {
        last = string
        didStart = true
        started?.resume(); started = nil
        if holdsWrites { await withCheckedContinuation { pending = $0 } }
    }
    func writeFileURLs(_ urls: [URL]) async {}
    func waitForWrite() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { pending?.resume(); pending = nil }
}

@MainActor private final class ColorTestSampler: ColorSampling {
    private var pending: CheckedContinuation<CommandlyColor?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func sample() async -> CommandlyColor? {
        await withCheckedContinuation {
            pending = $0
            started?.resume(); started = nil
        }
    }
    func waitForStart() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ color: CommandlyColor?) { pending?.resume(returning: color); pending = nil }
}
private struct ColorTestDictionary: DictionaryLookingUp {
    nonisolated func definition(for word: String) async -> String? { nil }
}
@MainActor private final class ColorTestFonts: FontCatalogProviding { let availableFamilies: [String] = [] }
