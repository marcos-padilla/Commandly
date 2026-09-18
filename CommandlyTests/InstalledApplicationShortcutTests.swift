import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Installed application shortcuts")
@MainActor
struct InstalledApplicationShortcutTests {
    private let first = LauncherHotKey(keyCode: 0, modifiers: [.command, .option])
    private let second = LauncherHotKey(keyCode: 2, modifiers: [.control, .option])

    @Test func preferencesRoundTripPreservesExistingMetadataAndRejectsMalformedSavedKeys() throws {
        let suite = "CommandlyTests.InstalledShortcuts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsApplicationPreferencesStore(defaults: defaults)
        #expect(store.load().hotKeys.isEmpty)
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = ["test.canvas": first]
        preferences.aliases = ["test.canvas": "Studio"]
        preferences.favoriteBundleIDs = ["test.canvas"]
        preferences.ranking = ["test.canvas": AppUsageRanking(openCount: 7, lastOpenedAt: nil)]
        store.save(preferences)
        #expect(store.load() == preferences)
        let malformed: [String: LauncherHotKey] = [
            "test.good": second,
            "bad/path": first,
            "test.unknown": LauncherHotKey(keyCode: 9_999, modifiers: .command),
            "test.typing": LauncherHotKey(keyCode: 0, modifiers: .shift),
            "test.bits": LauncherHotKey(keyCode: 0, modifiers: LauncherHotKeyModifiers(rawValue: 255))
        ]
        defaults.set(try JSONEncoder().encode(malformed), forKey: "apps.hotKeys")
        #expect(store.load().hotKeys == ["test.good": second])
        #expect(store.load().aliases == preferences.aliases)
    }

    @Test func assignmentConflictsNeverWriteAndDisabledOwnersDoNotReserveShortcuts() {
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = ["test.other": first]
        let store = InMemoryApplicationPreferencesStore(preferences: preferences)
        var registrations = 0
        let conflict = InstalledApplicationShortcuts.save(first, for: "test.canvas", store: store) {
            registrations += 1
            return [:]
        }
        #expect(conflict != nil)
        #expect(registrations == 0)
        #expect(store.load() == preferences)
        preferences.disabledBundleIDs.insert("test.other")
        store.save(preferences)
        #expect(InstalledApplicationShortcuts.save(first, for: "test.canvas", store: store, refreshRegistrations: { [:] }) == nil)
        #expect(store.load().hotKeys["test.other"] == first)
        #expect(InstalledApplicationShortcuts.bindings(in: store.load()).map(\.0) == ["test.canvas"])
    }

    @Test func nativeFailureRestoresPriorShortcutAndPreservesOtherChanges() {
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = ["test.canvas": first]
        let store = InMemoryApplicationPreferencesStore(preferences: preferences)
        var registrationSnapshots: [LauncherHotKey?] = []
        let error = InstalledApplicationShortcuts.save(second, for: "test.canvas", store: store) {
            registrationSnapshots.append(store.load().hotKeys["test.canvas"])
            var latest = store.load()
            latest.favoriteBundleIDs.insert("test.canvas")
            store.save(latest)
            return registrationSnapshots.count == 1 ? ["test.canvas": .unavailable] : [:]
        }
        #expect(error != nil)
        #expect(registrationSnapshots == [second, first])
        #expect(store.load().hotKeys["test.canvas"] == first)
        #expect(store.load().favoriteBundleIDs == ["test.canvas"])
    }

    @Test func removalWorksForDisabledAppAndDoesNotEraseOtherPreferences() {
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = ["test.canvas": first, "test.other": second]
        preferences.disabledBundleIDs = ["test.canvas"]
        preferences.aliases = ["test.canvas": "Studio"]
        let store = InMemoryApplicationPreferencesStore(preferences: preferences)
        #expect(InstalledApplicationShortcuts.save(nil, for: "test.canvas", store: store, refreshRegistrations: { [:] }) == nil)
        #expect(store.load().hotKeys == ["test.other": second])
        #expect(store.load().aliases == preferences.aliases)
        #expect(store.load().disabledBundleIDs == preferences.disabledBundleIDs)
    }

    @Test func invalidPlainTypingAndExcessiveAssignmentsAreRejected() {
        let store = InMemoryApplicationPreferencesStore()
        var refreshes = 0
        let invalid = [
            LauncherHotKey(keyCode: 0, modifiers: []),
            LauncherHotKey(keyCode: 0, modifiers: .shift),
            LauncherHotKey(keyCode: 9_999, modifiers: .command)
        ]
        for key in invalid {
            #expect(InstalledApplicationShortcuts.save(key, for: "test.canvas", store: store) {
                refreshes += 1
                return [:]
            } != nil)
        }
        #expect(refreshes == 0)
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = Dictionary(uniqueKeysWithValues: (0..<128).map { ("test.app\($0)", first) })
        store.save(preferences)
        #expect(InstalledApplicationShortcuts.save(second, for: "test.new", store: store, refreshRegistrations: { [:] }) != nil)
        #expect(store.load() == preferences)
    }

    @Test func existingShortcutOwnersKeepPriorityWhenAnotherAppIsEnabled() throws {
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = ["test.zebra": first, "test.alpha": first]
        let ordered = InstalledApplicationShortcuts.orderedBindings(in: preferences, previousOwners: ["test.zebra"])
        #expect(ordered.map(\.0) == ["test.zebra", "test.alpha"])
        let bindings = RuntimeGlobalShortcutCatalog.bindings(
            applicationHotKeys: [], wheelConfiguration: CommandWheelDefaults.configuration,
            installedApplicationHotKeys: ordered
        )
        let plan = GlobalShortcutPlan.resolve(bindings.map(\.registration))
        #expect(plan.issues[RuntimeGlobalShortcutCatalog.installedApplicationID("test.alpha")] == .duplicate(
            owner: RuntimeGlobalShortcutCatalog.installedApplicationID("test.zebra")
        ))
        #expect(plan.issues[RuntimeGlobalShortcutCatalog.installedApplicationID("test.zebra")] == nil)
    }

    @Test func installedAppsCannotTakeLauncherCommandsOrWheelShortcuts() {
        var wheel = CommandWheelDefaults.configuration
        wheel.isEnabled = true
        wheel.profiles[0].shortcut = second
        let bindings = RuntimeGlobalShortcutCatalog.bindings(
            applicationHotKeys: [(CommandID(rawValue: "test.command"), first)],
            wheelConfiguration: wheel,
            installedApplicationHotKeys: [
                ("test.launcher", LauncherHotKey(keyCode: 49, modifiers: .option)),
                ("test.command", first), ("test.wheel", second)
            ]
        )
        let plan = GlobalShortcutPlan.resolve(bindings.map(\.registration))
        for bundle in ["test.launcher", "test.command", "test.wheel"] {
            #expect(plan.issues[RuntimeGlobalShortcutCatalog.installedApplicationID(bundle)] != nil)
        }
        #expect(bindings.last?.route == .installedApplication(bundleIdentifier: "test.wheel"))
    }

    @Test func editorRecordingCancelAndFailedSaveKeepDraftAndRestoreShortcuts() {
        var recordedStates: [Bool] = []
        var writes = 0
        var saved = false
        var cancelled = false
        let model = InstalledApplicationShortcutEditorModel(
            bundleIdentifier: "test.canvas", applicationName: "Canvas", hotKey: first,
            saveAssignment: { _, _ in writes += 1; return "Unavailable" },
            onRecordingChange: { recordedStates.append($0) },
            onSaved: { saved = true }, onCancel: { cancelled = true }
        )
        model.hotKey = second
        model.recordingChanged(true)
        model.save()
        #expect(writes == 0)
        #expect(!model.canSave)
        model.recordingChanged(false)
        model.save()
        #expect(writes == 1)
        #expect(model.errorMessage == "Unavailable")
        #expect(model.hotKey == second)
        #expect(!saved)
        model.recordingChanged(true)
        model.cancel()
        #expect(cancelled)
        #expect(recordedStates == [true, false, true, false])
    }

    @Test func editorSaveUsesExactBundleAndExplicitRemoval() {
        var savedBundle: String?
        var savedShortcut: LauncherHotKey? = first
        var saved = false
        let model = InstalledApplicationShortcutEditorModel(
            bundleIdentifier: "test.canvas", applicationName: "Canvas", hotKey: first,
            saveAssignment: { bundle, key in savedBundle = bundle; savedShortcut = key; return nil },
            onSaved: { saved = true }, onCancel: {}
        )
        #expect(!model.canSave)
        model.hotKey = nil
        #expect(model.removesShortcut)
        model.save()
        #expect(saved)
        #expect(savedBundle == "test.canvas")
        #expect(savedShortcut == nil)
    }

    @Test func missingApplicationAssignmentCanBeRemovedWithoutLosingCurrentDraft() {
        var preferences = ApplicationPreferences.default
        preferences.hotKeys = ["test.canvas": first, "test.missing": second]
        let store = InMemoryApplicationPreferencesStore(preferences: preferences)
        let model = InstalledApplicationShortcutEditorModel(
            bundleIdentifier: "test.canvas", applicationName: "Canvas", hotKey: first,
            saveAssignment: { bundle, key in
                InstalledApplicationShortcuts.save(key, for: bundle, store: store, refreshRegistrations: { [:] })
            },
            loadAssignments: {
                store.load().hotKeys.map {
                    InstalledApplicationShortcutSummary(bundleIdentifier: $0.key, applicationName: $0.key, hotKey: $0.value)
                }
            },
            onSaved: {}, onCancel: {}
        )
        model.hotKey = second
        model.toggleOtherAssignments()
        #expect(model.otherAssignments.map(\.id) == ["test.missing"])
        model.recordingChanged(true)
        model.removeOtherAssignment("test.missing")
        #expect(store.load().hotKeys["test.missing"] == second)
        model.recordingChanged(false)
        model.removeOtherAssignment("test.missing")
        #expect(store.load().hotKeys["test.missing"] == nil)
        #expect(store.load().hotKeys["test.canvas"] == first)
        #expect(model.hotKey == second)
        #expect(model.otherAssignments.isEmpty)
        #expect(model.canSave)
    }
}
