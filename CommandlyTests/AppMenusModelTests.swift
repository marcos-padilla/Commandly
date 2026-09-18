@testable import Commandly
import SystemCompanionKit
import Foundation
import Infrastructure
import Testing

@MainActor struct AppMenusModelTests {
    @Test func openingLoadsFavoritesWithoutNativeCaptureOrOptIn() async throws {
        let client = MenuClient(items: [try menuItem()]); let store = MemoryFavorites()
        let model = AppMenusModel(client: client, favorites: store)
        model.open(); await model.waitForFavoritesForTesting()
        #expect(await client.calls.isEmpty)
        #expect(model.items.isEmpty && model.state == .idle && model.favoritesLoaded)
    }
    @Test func searchFavoritesAndInvocationUseActualSnapshotHandle() async throws {
        let first = try menuItem("Export Report"); let second = try menuItem("Copy Link")
        let client = MenuClient(items: [first, second]); let store = MemoryFavorites()
        let model = AppMenusModel(client: client, favorites: store)
        model.open(); await model.waitForFavoritesForTesting()
        model.readMenus(); await model.waitForOperationForTesting()
        #expect(model.state == .ready && model.items.count == 2)
        model.query = "menu report"; #expect(model.filteredItems == [first])
        model.query = ""; model.toggleFavorite(second); await model.waitForFavoritesForTesting()
        #expect(model.filteredItems.first == second)
        model.favoritesOnly = true; #expect(model.filteredItems == [second])
        #expect(await store.favorites == [second.identity])
        model.selection = second.handle; model.invokeSelection(); await model.waitForOperationForTesting()
        #expect(await client.calls.last == .invoke(second.handle))
        #expect(model.items.isEmpty && model.message == "The app accepted the menu action.")
        model.invokeSelection(); #expect(await client.calls.count == 2)
        model.stop()
    }
    @Test func disabledEntriesAndFilteredOutSelectionCannotInvoke() async throws {
        let disabled = try menuItem(enabled: false); let client = MenuClient(items: [disabled])
        let model = AppMenusModel(client: client, favorites: MemoryFavorites())
        model.readMenus(); await model.waitForOperationForTesting()
        model.selection = disabled.handle; model.invokeSelection()
        #expect(await client.calls == [.snapshot])
        model.stop()
    }
    @Test func lateSnapshotCannotReviveClosedLauncher() async throws {
        let client = MenuClient(items: [try menuItem()]); await client.hold()
        let model = AppMenusModel(client: client, favorites: MemoryFavorites())
        model.readMenus(); await client.waitForSnapshot(); model.stop(); await client.resume()
        await model.waitForOperationForTesting()
        #expect(model.state == .ended && model.items.isEmpty)
        model.stop()
    }
    @Test func unexpectedReplyAndUnknownInvocationOutcomeStayExplicit() async throws {
        let item = try menuItem(); let client = MenuClient(items: [item])
        let model = AppMenusModel(client: client, favorites: MemoryFavorites())
        await client.setReply(.enabled(true)); model.readMenus(); await model.waitForOperationForTesting()
        #expect(model.state == .failure(.invalidData))
        await client.setReply(.snapshot(.init(bundleIdentifier: "generated.fixture", items: [item])))
        model.readMenus(); await model.waitForOperationForTesting()
        await client.setReply(.invoked(.outcomeUnknown)); model.selection = item.handle
        model.invokeSelection(); await model.waitForOperationForTesting()
        #expect(model.message == "The action may have run. Check the app before trying again.")
        #expect(model.items.isEmpty)
        model.stop()
    }
    @Test func failedFavoritesLoadCannotOverwriteExistingStorage() async throws {
        let item = try menuItem(); let client = MenuClient(items: [item]); let store = MemoryFavorites(); await store.setFailure()
        let model = AppMenusModel(client: client, favorites: store)
        model.open(); await model.waitForFavoritesForTesting()
        model.readMenus(); await model.waitForOperationForTesting()
        model.toggleFavorite(item); await model.waitForFavoritesForTesting()
        #expect(await store.saves == 0 && !model.favoritesLoaded)
        model.stop()
    }
}
