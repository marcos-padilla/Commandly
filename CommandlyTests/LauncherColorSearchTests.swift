import AppKit
import CommandKit
import Foundation
import Testing
@testable import Commandly

@MainActor struct LauncherColorSearchTests {
    @Test func immediateReturnWaitsForColorSearchAndCopiesAlpha() async throws {
        let board = InMemoryPasteboard()
        let model = makeModel(board: board)
        model.query = "#966A5E80"
        await model.confirmSelectionAndWaitForTesting()
        #expect(board.currentValue == "#966A5E80")
        #expect(model.selectedItem?.section == .color)
        #expect(model.route == .root)
        #expect(model.colorSearch.selectedFormat == .hexWithAlpha)
        model.resetAfterDismiss()
    }

    @Test func allRootFormatsHaveTypedActionsAndNoCalculatorOrAutocomplete() async throws {
        let board = InMemoryPasteboard()
        let model = makeModel(board: board)
        model.query = "hsl(120 100% 50% / 25%)"
        await model.flushSearchForTesting()
        let result = try #require(model.colorSearch.result)
        #expect(model.rootItems.first?.action == .colorPrimary(resultID: result.id))
        #expect(model.rootItems.contains { $0.section == .calculator } == false)
        #expect(model.autocompleteCompletion == nil)
        model.presentApplicationActionsForSelection()
        await model.waitForConfirmationForTesting()
        #expect(model.colorSearch.showsActions)
        #expect(model.rootActionsMenuItems.map(\.id) == CommandlyColorFormat.allCases.map(\.copyActionID))
        for format in CommandlyColorFormat.allCases {
            model.performFooterAction(format.copyActionID)
            await model.waitForConfirmationForTesting()
            await model.colorSearch.flushCopyForTesting()
            #expect(board.currentValue == result.color.formatted(format))
        }
        model.resetAfterDismiss()
        #expect(model.colorSearch.result == nil)
    }

    @Test func queryReplacementRejectsOldCardAndEscapeDismissesActionsFirst() async throws {
        let board = InMemoryPasteboard()
        let model = makeModel(board: board)
        model.query = "#F00"
        await model.flushSearchForTesting()
        let first = try #require(model.colorSearch.result)
        model.colorSearch.presentActions(resultID: first.id)
        #expect(model.handleEscape())
        #expect(!model.colorSearch.showsActions)
        #expect(model.query == "#F00")
        model.query = "#0F0"
        model.colorSearch.perform(CommandlyColorFormat.hsl.copyActionID, resultID: first.id)
        await model.colorSearch.flushCopyForTesting()
        #expect(board.currentValue == nil)
        model.query = "rgbjunk(1,2,3)"
        await model.flushSearchForTesting()
        #expect(model.colorSearch.result == nil)
        #expect(model.rootItems.contains { $0.section == .color } == false)
        model.resetAfterDismiss()
    }

    private func makeModel(board: InMemoryPasteboard) -> LauncherViewModel {
        // A named isolated pasteboard prevents the existing history store from reading .general.
        let store = ClipboardHistoryStore(pasteboard: NSPasteboard(name: .init("CommandlyTests.color.\(UUID().uuidString)")))
        return LauncherViewModel(clipboardHistoryStore: store, pasteboard: board, placeholderItems: [])
    }
}
