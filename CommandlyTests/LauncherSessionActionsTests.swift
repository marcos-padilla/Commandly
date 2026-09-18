import CommandKit
import SwiftUI
import Testing
@testable import Commandly

@MainActor
struct LauncherSessionActionsTests {
    @Test func sharedMenuRejectsClosedMissingAndNewlyDisabledActions() {
        let model = MenuFixture()
        let session = makeSession(model)
        #expect(session.usesSharedActionsMenu)
        #expect(!session.performMenuAction(MenuFixture.copyID))
        model.showsActionsMenu = true
        #expect(!session.performMenuAction(.init(rawValue: "missing")))
        model.copyEnabled = false
        #expect(!session.performMenuAction(MenuFixture.copyID))
        #expect(model.showsActionsMenu)
        #expect(model.performed.isEmpty)
        model.copyEnabled = true
        #expect(session.performMenuAction(MenuFixture.copyID))
        #expect(!model.showsActionsMenu)
        #expect(model.wasMenuClosedAtDispatch)
        #expect(model.performed == [MenuFixture.copyID])
        #expect(!session.performMenuAction(MenuFixture.copyID))
    }

    @Test func customPanelKeepsItsOwnPresentationAndDispatch() {
        let model = MenuFixture()
        model.presentsOwnActionsMenu = true
        model.showsActionsMenu = true
        let session = makeSession(model)
        #expect(!session.usesSharedActionsMenu)
        #expect(!session.performMenuAction(MenuFixture.copyID))
        #expect(model.showsActionsMenu)
        #expect(model.performed.isEmpty)
    }

    private func makeSession(_ model: MenuFixture) -> LauncherApplicationSession {
        LauncherApplicationSession(
            manifest: .init(id: .init(rawValue: "test.actions"), title: "Test Actions",
                            subtitle: "Generated menu", systemImage: "list.bullet", category: .productivity, mode: .view),
            model: model
        ) { _ in EmptyView() }
    }

    private final class MenuFixture: LauncherApplicationModel {
        static let copyID = CommandActionID(rawValue: "test.copy")
        var statusMessage: String?
        var footerActions: [CommandActionDescriptor] { [] }
        var menuActions: [CommandActionDescriptor] { [.init(id: Self.copyID, title: "Copy", isEnabled: copyEnabled)] }
        var showsActionsMenu = false
        var presentsOwnActionsMenu = false
        var copyEnabled = true
        var performed: [CommandActionID] = []
        var wasMenuClosedAtDispatch = false
        func moveSelection(offset: Int) {}
        func perform(_ id: CommandActionID) {
            wasMenuClosedAtDispatch = !showsActionsMenu
            performed.append(id)
        }
    }
}
