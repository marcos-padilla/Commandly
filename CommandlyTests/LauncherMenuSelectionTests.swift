import Foundation
import Testing
@testable import Commandly

struct LauncherMenuSelectionTests {
    @Test func keyboardMovementWrapsThroughOnlyEnabledVisibleItems() {
        var selection = LauncherMenuSelection<String>()
        let enabled = ["open", "copy", "reveal"]
        selection.reconcile(with: enabled)
        #expect(selection.activationID(in: enabled) == "open")
        selection.move(by: -1, in: enabled)
        #expect(selection.activationID(in: enabled) == "reveal")
        selection.move(by: 1, in: enabled)
        selection.move(by: 1, in: enabled)
        #expect(selection.activationID(in: enabled) == "copy")
        selection.select("disabled", in: enabled)
        #expect(selection.activationID(in: enabled) == "copy")
    }

    @Test func filteringReconcilesSelectionAndEmptyResultsCannotActivate() {
        var selection = LauncherMenuSelection<String>()
        selection.reconcile(with: ["open", "copy"], preferredID: "copy")
        #expect(selection.selectedID == "copy")
        #expect(selection.activationID(in: ["open"]) == nil)
        selection.reconcile(with: ["open"])
        #expect(selection.selectedID == "open")
        selection.reconcile(with: [])
        #expect(selection.activationID(in: []) == nil)
        selection.move(by: 1, in: [])
        #expect(selection.selectedID == nil)
        selection.reconcile(with: ["reveal"])
        #expect(selection.selectedID == "reveal")
    }

    @Test @MainActor func dismissingMenusPreservesCurrentOwnershipAndRunsOnce() {
        let state = LauncherTransientMenuState()
        let first = UUID()
        let second = UUID()
        var firstDismissals = 0
        var secondDismissals = 0
        var restoredFocus: [Bool] = []
        state.present(id: first) {
            firstDismissals += 1
            restoredFocus.append($0)
        }
        state.present(id: second) {
            secondDismissals += 1
            restoredFocus.append($0)
        }
        #expect(firstDismissals == 1)
        state.remove(id: first)
        #expect(state.dismiss())
        #expect(secondDismissals == 1)
        #expect(state.dismiss() == false)
        #expect(restoredFocus == [false, true])
    }
}
