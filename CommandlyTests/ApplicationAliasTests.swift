import Foundation
import CommandKit
import Infrastructure
import SearchKit
import Testing
@testable import Commandly

struct ApplicationAliasTests {
    @Test func aliasesNormalizeUnicodeAndRejectOversizedOrControlInput() throws {
        #expect(try ApplicationAlias.normalized("  Design \n Studio\t ") == "Design Studio")
        #expect(try ApplicationAlias.normalized("👨‍👩‍👧‍👦 家") == "👨‍👩‍👧‍👦 家")
        #expect(try ApplicationAlias.normalized(" \n ") == nil)
        #expect(throws: ApplicationAlias.ValidationError.tooLong) {
            try ApplicationAlias.normalized(String(repeating: "👨‍👩‍👧‍👦", count: 65))
        }
        #expect(throws: ApplicationAlias.ValidationError.invalidCharacters) {
            try ApplicationAlias.normalized("bad\u{0}alias")
        }
        #expect(throws: ApplicationAlias.ValidationError.alreadyAssigned) {
            try ApplicationAlias.validate(" CAFÉ ", for: "new.app", aliases: ["old.app": "cafe"])
        }
        #expect(try ApplicationAlias.validate("CAFÉ", for: "old.app", aliases: ["old.app": "cafe"]) == "CAFÉ")
    }

    @Test @MainActor func aliasSearchRetainsIdentityCanonicalNamesAndExistingDisabledPolicy() async throws {
        let apps = [
            InstalledApplicationSnapshot(bundleIdentifier: "com.example.design", name: "Canvas", path: "/Applications/Canvas.app"),
            InstalledApplicationSnapshot(bundleIdentifier: "com.example.work", name: "Studio", path: "/Applications/Studio.app")
        ]
        let provider = ApplicationSearchProvider(
            applications: apps,
            favoriteBundleIDs: ["com.example.work"],
            disabledBundleIDs: ["com.example.design"],
            ranking: ["com.example.work": AppUsageRanking(openCount: 100, lastOpenedAt: nil)],
            aliases: ["com.example.design": "Stúdio"]
        )
        let service = CompositeSearchService(providers: [provider])
        let matched = try await service.search(SearchQuery(text: "STUDIO"))
        #expect(matched.items.first?.id == "com.example.design")
        #expect(matched.items.first?.title == "Canvas")
        #expect(matched.items.first?.subtitle == "Alias: Stúdio")
        let canonical = try await provider.search(SearchQuery(text: "Canvas"))
        #expect(canonical.items.map(\.id) == ["com.example.design"])
        let empty = try await provider.search(SearchQuery(text: ""))
        #expect(empty.items.map(\.id) == ["com.example.work"])
        let absent = try await provider.search(SearchQuery(text: "no match"))
        #expect(absent.items.isEmpty)
    }

    @Test @MainActor func aliasStorageAddsNoMigrationRequirementAndPreservesOtherPreferences() throws {
        let suite = "CommandlyTests.ApplicationAlias.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsApplicationPreferencesStore(defaults: defaults)
        #expect(store.load().aliases.isEmpty)
        var preferences = ApplicationPreferences.default
        preferences.favoriteBundleIDs = ["com.example.design"]
        preferences.disabledBundleIDs = ["com.example.old"]
        preferences.autoQuitBundleIDs = ["com.example.work"]
        preferences.ranking["com.example.design"] = AppUsageRanking(openCount: 3, lastOpenedAt: nil)
        preferences.aliases["com.example.design"] = "Studio"
        store.save(preferences)
        #expect(store.load() == preferences)
        preferences.aliases["com.example.design"] = nil
        store.save(preferences)
        #expect(store.load() == preferences)
    }

    @Test @MainActor func editorValidatesWithoutSavingAndMergesTheLatestPreferences() {
        var original = ApplicationPreferences.default
        original.aliases = ["com.example.other": "work"]
        let store = InMemoryApplicationPreferencesStore(preferences: original)
        let observation = AliasEditorObservation()
        let model = makeEditor(store: store, observation: observation)
        #expect(model.canSave == false)
        model.alias = "WORK"
        #expect(model.validationMessage != nil)
        model.save()
        #expect(store.load() == original)
        #expect(observation.saved.isEmpty)

        model.alias = " Design  Desk "
        #expect(model.canSave)
        var latest = store.load()
        latest.favoriteBundleIDs.insert("com.example.design")
        latest.ranking["com.example.design"] = AppUsageRanking(openCount: 9, lastOpenedAt: nil)
        store.save(latest)
        model.save()
        #expect(store.load().alias(for: "com.example.design") == "Design Desk")
        #expect(store.load().favoriteBundleIDs == latest.favoriteBundleIDs)
        #expect(store.load().ranking == latest.ranking)
        #expect(observation.saved == ["Design Desk"])

        let removal = makeEditor(store: store, observation: observation)
        removal.alias = ""
        #expect(removal.canSave)
        removal.save()
        #expect(store.load().alias(for: "com.example.design") == nil)
        #expect(observation.saved == ["Design Desk", nil])
    }

    @Test @MainActor func cancellingAliasEditingNeverChangesPersistence() {
        let store = InMemoryApplicationPreferencesStore()
        let observation = AliasEditorObservation()
        let model = makeEditor(store: store, observation: observation)
        model.alias = "Unfinished nickname"
        model.cancel()
        #expect(observation.didCancel)
        #expect(observation.saved.isEmpty)
        #expect(store.load().aliases.isEmpty)
    }

    @Test @MainActor func launcherAliasActionSavesSearchMetadataAndEscapeCancelsTheNextDraft() async throws {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.design", name: "Canvas", path: "/Applications/Canvas.app"
        )
        let store = InMemoryApplicationPreferencesStore()
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app]),
            applicationPreferencesStore: store
        )
        await viewModel.flushSearchForTesting()
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(bundleIdentifier: app.bundleIdentifier, name: app.name, path: app.path)
        ]
        viewModel.select("app:\(app.bundleIdentifier)")
        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        #expect(viewModel.filteredApplicationActions.contains {
            $0.id == BuiltInCommandActionID.editApplicationAlias && $0.title == "Set Alias…"
        })
        viewModel.performApplicationAction(BuiltInCommandActionID.editApplicationAlias)
        await waitForAliasEditor(viewModel)
        let editor = try #require(viewModel.applicationAliasEditor)
        #expect(viewModel.showsApplicationActionsPanel == false)
        editor.alias = "Creative desk"
        let focusBeforeSave = viewModel.searchFocusEpoch
        editor.save()
        #expect(viewModel.applicationAliasEditor == nil)
        #expect(viewModel.searchFocusEpoch > focusBeforeSave)
        #expect(store.load().alias(for: app.bundleIdentifier) == "Creative desk")
        viewModel.query = "Creative desk"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.contains { $0.id == "app:\(app.bundleIdentifier)" && $0.title == "Canvas" })

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        #expect(viewModel.filteredApplicationActions.contains {
            $0.id == BuiltInCommandActionID.editApplicationAlias && $0.title == "Edit Alias…"
        })
        viewModel.performApplicationAction(BuiltInCommandActionID.editApplicationAlias)
        await waitForAliasEditor(viewModel)
        let nextEditor = try #require(viewModel.applicationAliasEditor)
        #expect(nextEditor.alias == "Creative desk")
        nextEditor.alias = "Discard this draft"
        let focusBeforeEscape = viewModel.searchFocusEpoch
        #expect(viewModel.handleEscape())
        #expect(viewModel.applicationAliasEditor == nil)
        #expect(viewModel.searchFocusEpoch > focusBeforeEscape)
        #expect(store.load().alias(for: app.bundleIdentifier) == "Creative desk")
        viewModel.resetAfterDismiss()
    }

    @MainActor private func waitForAliasEditor(_ viewModel: LauncherViewModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while viewModel.applicationAliasEditor == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    @MainActor private func makeEditor(
        store: any ApplicationPreferencesStoring,
        observation: AliasEditorObservation
    ) -> ApplicationAliasEditorModel {
        ApplicationAliasEditorModel(
            bundleIdentifier: "com.example.design", applicationName: "Canvas", preferencesStore: store,
            onSaved: { observation.saved.append($0) }, onCancel: { observation.didCancel = true }
        )
    }
}

@MainActor
private final class AliasEditorObservation {
    var saved: [String?] = []
    var didCancel = false
}
