import Foundation
import AppKit
import Testing
@testable import Commandly
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability
import Infrastructure
import DesignSystem
import SearchKit
import CalculatorKit
import SwiftUI

struct CommandlyTests {
    @Test @MainActor func compactWindowChromeRehidesAWindowTitleRestoredBySwiftUI() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let coordinator = CompactWindowChrome.Coordinator()

        coordinator.configure(window, hidesZoomButton: true)
        window.title = "Commandly Settings"
        window.titleVisibility = .visible
        coordinator.configure(window, hidesZoomButton: true)

        #expect(window.title.isEmpty)
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
    }

    @Test @MainActor func dependencyContainerBootstrapsToRootWhenOnboarded() {
        let container = makeTestContainer(hasCompletedOnboarding: true)
        #expect(container.dependencies.metadata.name == "Commandly")
        #expect(container.appState.route == .root)
        let viewModel = container.makeRootViewModel()
        #expect(viewModel.status == "Foundation ready")
        #expect(viewModel.message == "Feature development has not started yet.")
    }

    @Test @MainActor func bootstrapShowsOnboardingWhenIncomplete() {
        let container = makeTestContainer(hasCompletedOnboarding: false)
        #expect(container.appState.route == .onboarding)
    }

    @Test @MainActor func routerUpdatesAppState() {
        let container = makeTestContainer(hasCompletedOnboarding: true)
        container.router.navigate(to: .settings)
        #expect(container.appState.route == .settings)
    }

    @Test @MainActor func onboardingViewModelAdvancesToReady() {
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener()
        )

        #expect(viewModel.step == .welcome)
        #expect(viewModel.primaryActionTitle == "Start Setup")
        #expect(viewModel.canGoBack == false)

        viewModel.advance()
        #expect(viewModel.step == .features)
        #expect(viewModel.canGoBack == true)

        viewModel.goBack()
        #expect(viewModel.step == .welcome)

        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        #expect(viewModel.step == .ready)
        #expect(viewModel.primaryActionTitle == "Open Commandly")

        viewModel.advance()
        #expect(viewModel.hotkeyPhase == .celebrating)
        #expect(viewModel.hasConfirmedOptionSpaceHotkey == false)
    }

    @Test @MainActor func optionSpaceHotkeyConfirmsAndCelebrates() async {
        let settings = InMemoryAppSettingsStore()
        var finished = false
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: settings,
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .ready,
            onFinished: { finished = true }
        )

        viewModel.handleOptionSpaceHotkey()
        #expect(viewModel.hotkeyPhase == .celebrating)
        #expect(viewModel.hasConfirmedOptionSpaceHotkey)
        #expect(settings.load().hasConfirmedOptionSpaceHotkey)
        #expect(viewModel.showsPrimaryAction == false)

        await waitUntil(timeoutNanoseconds: 2_500_000_000) { finished }
        #expect(finished)
        #expect(viewModel.hotkeyPhase == .finished)
    }

    @Test @MainActor func pressedKeysUpdateFromMonitorCallback() {
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .ready
        )

        viewModel.updatePressedKeys([.a, .leftShift])
        #expect(viewModel.pressedKeyIDs == [.a, .leftShift])
        #expect(MacBookProKeyboardLayout.keyIDs(forKeyCode: 0) == [.a])
        #expect(MacBookProKeyboardLayout.keyIDs(forKeyCode: 49) == [.space])
        #expect(MacBookProKeyboardLayout.keyIDs(forKeyCode: 58) == [.leftOption])
    }

    @Test @MainActor func finishingOnboardingNavigatesToRoot() {
        let store = InMemoryOnboardingStatusStore()
        let container = makeTestContainer(
            hasCompletedOnboarding: false,
            onboardingStatusStore: store
        )
        #expect(container.appState.route == .onboarding)

        let viewModel = container.makeOnboardingViewModel()
        viewModel.finish()

        #expect(store.hasCompletedOnboarding)
        #expect(container.appState.route == .root)
    }

    @Test @MainActor func appRuntimeHidesOnboardingAfterFinishCallback() {
        let store = InMemoryOnboardingStatusStore()
        let container = makeTestContainer(
            hasCompletedOnboarding: false,
            onboardingStatusStore: store
        )
        let runtime = AppRuntime(container: container)
        #expect(runtime.showsOnboarding)

        let viewModel = runtime.makeOnboardingViewModel()
        viewModel.finish()

        #expect(runtime.showsOnboarding == false)
        #expect(container.appState.route == .root)
    }

    @Test @MainActor func settingsViewModelPersistsGeneralPreferences() {
        let settings = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(
            settingsStore: settings,
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .testing
            )
        )

        viewModel.setPrefersCommandlyEmojiPicker(true)
        viewModel.setAppearance(.dark)
        viewModel.setTextSize(.larger)
        viewModel.setViewMode(.compact)
        viewModel.setShowMenuBarIcon(false)

        let loaded = settings.load()
        #expect(loaded.prefersCommandlyEmojiPicker)
        #expect(loaded.appearance == .dark)
        #expect(loaded.textSize == .larger)
        #expect(loaded.viewMode == .compact)
        #expect(loaded.showMenuBarIcon == false)
    }

    @Test func textSizePreferenceScaleFactorsMatchDesignTokens() {
        #expect(AppTextSizePreference.standard.scaleFactor == CommandlyTextScale.standard)
        #expect(AppTextSizePreference.larger.scaleFactor == CommandlyTextScale.larger)
        #expect(AppTextSizePreference.larger.scaleFactor > AppTextSizePreference.standard.scaleFactor)
    }

    @Test @MainActor func settingsTextSizeChangeNotifiesRuntimeCallback() {
        let settings = InMemoryAppSettingsStore()
        var received: AppTextSizePreference?
        let viewModel = SettingsViewModel(
            settingsStore: settings,
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .testing
            ),
            onTextSizeChange: { received = $0 }
        )

        viewModel.setTextSize(.larger)

        #expect(received == .larger)
        #expect(settings.load().textSize == .larger)
    }

    @Test @MainActor func appRuntimeTracksTextSizeFromSettings() {
        let settings = InMemoryAppSettingsStore(
            settings: AppSettings(
                opensAtLogin: false,
                prefersCommandlyEmojiPicker: false,
                hasConfirmedOptionSpaceHotkey: false,
                showMenuBarIcon: true,
                appearance: .system,
                textSize: .larger,
                viewMode: .comfortable
            )
        )
        let container = makeTestContainer(
            hasCompletedOnboarding: true,
            appSettingsStore: settings
        )
        let runtime = AppRuntime(container: container)
        #expect(runtime.textSize == .larger)

        let viewModel = runtime.makeSettingsViewModel()
        viewModel.setTextSize(.standard)
        #expect(runtime.textSize == .standard)
    }

    @Test func viewModeDensityMatchesDesignTokens() {
        #expect(AppViewModePreference.comfortable.layoutDensity == .comfortable)
        #expect(AppViewModePreference.compact.layoutDensity == .compact)
        #expect(
            AppViewModePreference.compact.layoutDensity.launcherHeight
                < AppViewModePreference.comfortable.layoutDensity.launcherHeight
        )
    }

    @Test @MainActor func settingsViewModeChangeNotifiesRuntimeCallback() {
        let settings = InMemoryAppSettingsStore()
        var received: AppViewModePreference?
        let viewModel = SettingsViewModel(
            settingsStore: settings,
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .testing
            ),
            onViewModeChange: { received = $0 }
        )

        viewModel.setViewMode(.compact)

        #expect(received == .compact)
        #expect(settings.load().viewMode == .compact)
    }

    @Test @MainActor func launcherOpensClipboardHistoryApplication() {
        let store = ClipboardHistoryStore()
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: store
        )
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        #expect(viewModel.route == .application(BuiltInCommandID.clipboardHistory))
        #expect(viewModel.activeApplicationModel(as: ClipboardHistoryViewModel.self) != nil)
        #expect(viewModel.contextTitle == "Clipboard History")
        #expect(viewModel.footerActions.contains { $0.id == BuiltInCommandActionID.copy })
    }

    @Test @MainActor func launcherOpensFileSearchApplication() async throws {
        let item = FileSearchItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/Plan.pdf"),
            name: "Plan.pdf",
            parentPath: "/Users/test/Documents",
            kind: .file,
            contentTypeIdentifier: "com.adobe.pdf",
            contentTypeDescription: "PDF document"
        )
        let service = InMemoryFileSearchService(items: [item])
        let viewModel = LauncherViewModel(fileSearchService: service)
        viewModel.selectedID = BuiltInCommandID.searchFiles.rawValue

        viewModel.confirmSelection()

        #expect(viewModel.route == .application(BuiltInCommandID.searchFiles))
        let fileViewModel = try #require(
            viewModel.activeApplicationModel(as: FileSearchViewModel.self)
        )
        await fileViewModel.flushSearchForTesting()
        #expect(fileViewModel.results == [item])
        #expect(viewModel.footerActions.first?.id == BuiltInCommandActionID.openFile)
    }

    @Test @MainActor func launcherRegistryRejectsDuplicateApplicationIdentifiers() throws {
        let registry = LauncherApplicationRegistry()
        try registry.register(TestLauncherApplication())

        do {
            try registry.register(TestLauncherApplication())
            Issue.record("Expected duplicate application registration to fail")
        } catch let error as LauncherApplicationRegistryError {
            #expect(error == .duplicateApplication(TestLauncherApplication.id))
        }
    }

    @Test @MainActor func launcherRegistryBuildsTypedHierarchy() throws {
        let registry = LauncherApplicationRegistry()
        let groupID = CommandID(rawValue: "test.group")
        try registry.register(
            .group(id: groupID, title: "Test Group", order: 10)
        )
        try registry.register(TestLauncherApplication(parentID: groupID))

        #expect(registry.rootDefinitions().map(\.id) == [groupID])
        #expect(registry.children(of: groupID).map(\.id) == [TestLauncherApplication.id])
        #expect(registry.definition(for: groupID)?.kind == .group)
        #expect(registry.definition(for: TestLauncherApplication.id)?.kind == .application)
    }

    @Test @MainActor func launcherRegistryRejectsMissingParents() {
        let registry = LauncherApplicationRegistry()
        let parentID = CommandID(rawValue: "test.missing-parent")

        do {
            try registry.register(TestLauncherApplication(parentID: parentID))
            Issue.record("Expected missing parent registration to fail")
        } catch let error as LauncherApplicationRegistryError {
            #expect(
                error == .missingParent(
                    child: TestLauncherApplication.id,
                    parent: parentID
                )
            )
        } catch {
            Issue.record("Unexpected registry error: \(error)")
        }
    }

    @Test @MainActor func aliasesParticipateInSearchAndDisabledParentsHideChildren() async throws {
        let preferences = InMemoryLauncherApplicationPreferencesStore()
        let registry = LauncherApplicationRegistry(preferencesStore: preferences)
        let groupID = CommandID(rawValue: "test.group")
        try registry.register(.group(id: groupID, title: "Test Group"))
        try registry.register(TestLauncherApplication(parentID: groupID))

        var appPreferences = LauncherApplicationPreferences.empty
        appPreferences.alias = "rocket"
        registry.savePreferences(appPreferences, for: TestLauncherApplication.id)

        let result = try await CommandSearchProvider(manifests: registry.allManifests())
            .search(SearchQuery(text: "rocket"))
        #expect(result.items.map(\.id) == [TestLauncherApplication.id.rawValue])

        var groupPreferences = LauncherApplicationPreferences.empty
        groupPreferences.isEnabled = false
        registry.savePreferences(groupPreferences, for: groupID)

        #expect(registry.allManifests().isEmpty)
        #expect(registry.enabledApplication(for: TestLauncherApplication.id) == nil)
    }

    @Test @MainActor func declaredClipboardConfigurationControlsNewSessions() throws {
        let preferences = InMemoryLauncherApplicationPreferencesStore()
        let registry = LauncherApplicationRegistry.makeBuiltIn(preferencesStore: preferences)
        var appPreferences = LauncherApplicationPreferences.empty
        appPreferences.configuration["defaultFilter"] = .text(ClipboardHistoryFilter.image.rawValue)
        registry.savePreferences(appPreferences, for: BuiltInCommandID.clipboardHistory)
        let viewModel = LauncherViewModel(
            applicationRegistry: registry,
            placeholderItems: []
        )

        viewModel.launch(BuiltInCommandID.clipboardHistory)

        let clipboardModel = try #require(
            viewModel.activeApplicationModel(as: ClipboardHistoryViewModel.self)
        )
        #expect(clipboardModel.filter == .image)
    }

    @Test @MainActor func applicationSettingsModelPersistsSchemaValues() throws {
        let preferences = InMemoryLauncherApplicationPreferencesStore()
        let registry = LauncherApplicationRegistry.makeBuiltIn(preferencesStore: preferences)
        var changeCount = 0
        let model = LauncherApplicationsSettingsModel(
            registry: registry,
            onPreferencesChange: { changeCount += 1 }
        )

        let initialAliases = registry.allDefinitions()
            .filter { $0.kind != .group }
            .compactMap { registry.resolvedSettings(for: $0.id)?.alias }
        #expect(initialAliases.isEmpty == false)
        #expect(initialAliases.allSatisfy { $0.isEmpty })

        model.select(BuiltInCommandID.searchFiles)
        model.setAlias("finder", for: BuiltInCommandID.searchFiles)
        let hotKey = LauncherHotKey(keyCode: 3, modifiers: [.command, .option])
        model.setHotKey(hotKey, for: BuiltInCommandID.searchFiles)
        model.setConfiguration(
            .boolean(false),
            variable: "showsDetails",
            for: BuiltInCommandID.searchFiles
        )

        let settings = try #require(registry.resolvedSettings(for: BuiltInCommandID.searchFiles))
        #expect(settings.alias == "finder")
        #expect(settings.hotKey == hotKey)
        #expect(settings.value(for: "showsDetails") == .boolean(false))
        #expect(changeCount == 3)
    }

    @Test @MainActor func applicationHotkeyPlanRejectsDuplicatesAndInvalidShortcuts() {
        let firstID = CommandID(rawValue: "hotkey.first")
        let secondID = CommandID(rawValue: "hotkey.second")
        let invalidID = CommandID(rawValue: "hotkey.invalid")
        let shortcut = LauncherHotKey(keyCode: 8, modifiers: [.command, .option])
        let invalid = LauncherHotKey(keyCode: 8, modifiers: [])

        let plan = ApplicationHotkeyPlan.resolve([
            (firstID, shortcut),
            (secondID, shortcut),
            (invalidID, invalid),
        ])

        #expect(plan.registrations.map(\.0) == [firstID])
        #expect(plan.issues[secondID] == .duplicate(firstID))
        #expect(plan.issues[invalidID] == .unavailable)
    }

    @Test @MainActor func applicationPreferencesRoundTripNonSecretValues() throws {
        let suiteName = "CommandlyTests.LauncherApplicationPreferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsLauncherApplicationPreferencesStore(defaults: defaults)
        let id = CommandID(rawValue: "test.persisted")
        let hotKey = LauncherHotKey(
            keyCode: 9,
            modifiers: [.command, .shift]
        )
        let expected = LauncherApplicationPreferences(
            alias: "voice",
            hotKey: hotKey,
            hasHotKeyOverride: true,
            isEnabled: false,
            configuration: [
                "prompt": .text("Concise"),
                "count": .integer(3),
                "temperature": .decimal(0.2),
                "localOnly": .boolean(true),
            ]
        )

        store.save(expected, for: id)

        #expect(store.preferences(for: id) == expected)
        #expect(hotKey.displayTitle == "⇧⌘V")
    }

    @Test @MainActor func registeredApplicationLaunchesWithoutRootFeatureBranch() throws {
        let registry = LauncherApplicationRegistry()
        try registry.register(TestLauncherApplication())
        let viewModel = LauncherViewModel(
            applicationRegistry: registry,
            placeholderItems: []
        )

        viewModel.launch(TestLauncherApplication.id)

        #expect(viewModel.route == .application(TestLauncherApplication.id))
        #expect(viewModel.contextTitle == "Test Application")
        #expect(viewModel.activeApplicationModel(as: TestLauncherApplicationModel.self) != nil)
        #expect(viewModel.footerActions.first?.id == TestLauncherApplication.primaryActionID)
    }

    @Test @MainActor func launcherFileArtworkCoversCommonFileFamilies() {
        let cases: [(String, LauncherFileArtwork, String)] = [
            ("report.pdf", .pdf, "doc.richtext.fill"),
            ("budget.xlsx", .spreadsheet, "tablecells.fill"),
            ("slides.key", .presentation, "rectangle.fill.on.rectangle.fill"),
            ("archive.zip", .archive, "archivebox.fill"),
            ("App.swift", .sourceCode, "chevron.left.forwardslash.chevron.right"),
            ("photo.heic", .image, "photo.fill"),
            ("recording.m4a", .audio, "speaker.wave.2.fill"),
            ("clip.mov", .video, "film.fill"),
            ("bookmark.webloc", .web, "globe.americas.fill"),
            ("font.otf", .font, "textformat"),
            ("notes.md", .text, "doc.text.fill"),
            ("unknown.data", .generic, "doc.fill")
        ]

        for (filename, expectedArtwork, expectedSymbol) in cases {
            let artwork = LauncherFileArtwork(fileURL: URL(fileURLWithPath: "/tmp/\(filename)"))
            #expect(artwork == expectedArtwork)
            #expect(artwork.symbolName == expectedSymbol)
        }
    }

    @Test @MainActor func launcherCommandArtworkUsesFilledVariants() {
        #expect(LauncherCommandArtwork.filledSymbol(for: "clipboard") == "clipboard.fill")
        #expect(LauncherCommandArtwork.filledSymbol(for: "gearshape") == "gearshape.fill")
        #expect(LauncherCommandArtwork.filledSymbol(for: "rectangle.split.2x1") == "rectangle.split.2x1.fill")
    }

    @Test @MainActor func fileSearchForwardsQueryContentAndTypeFilter() async throws {
        let service = InMemoryFileSearchService()
        let viewModel = FileSearchViewModel(
            searchService: service,
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            pasteboard: InMemoryPasteboard()
        )
        viewModel.query = "quarterly revenue"
        viewModel.category = .documents

        await viewModel.flushSearchForTesting()

        let requests = await service.requests
        let request = try #require(requests.last)
        #expect(request.query.text == "quarterly revenue")
        #expect(request.query.limit == 100)
        #expect(request.category == .documents)
        #expect(request.includesFileNames)
        #expect(request.includesFileContents)
        #expect(request.includesMetadata)
        #expect(request.includesTags)
        #expect(requests.count == 1)
    }

    @Test @MainActor func fileSearchAppliesCombinedIndexSnapshotAtomically() async {
        let filenameHit = FileSearchItem(
            url: URL(fileURLWithPath: "/Users/test/Desktop/wpb_hoa_contacts.csv"),
            name: "wpb_hoa_contacts.csv",
            parentPath: "/Users/test/Desktop",
            kind: .file,
            contentTypeIdentifier: "public.comma-separated-values-text",
            contentTypeDescription: "CSV document"
        )
        let contentHit = FileSearchItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/association-notes.txt"),
            name: "association-notes.txt",
            parentPath: "/Users/test/Documents",
            kind: .file,
            contentTypeIdentifier: "public.plain-text",
            contentTypeDescription: "Plain text",
            matchKind: .contents
        )
        let service = InMemoryFileSearchService(items: [filenameHit, contentHit])
        let viewModel = FileSearchViewModel(
            searchService: service,
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            pasteboard: InMemoryPasteboard()
        )
        viewModel.query = "wpb_hoa_contacts.csv"

        await viewModel.flushSearchForTesting()

        #expect(viewModel.results == [filenameHit, contentHit])
        #expect(viewModel.loadState == .loaded)
        #expect(await service.requests.count == 1)
    }

    @Test @MainActor func fileSearchSelectionCopiesPathAndHandlesMissingAccess() async {
        let item = FileSearchItem(
            url: URL(fileURLWithPath: "/Users/test/Pictures/Receipt.png"),
            name: "Receipt.png",
            parentPath: "/Users/test/Pictures",
            kind: .file,
            contentTypeIdentifier: "public.png",
            contentTypeDescription: "PNG image"
        )
        let pasteboard = InMemoryPasteboard()
        let viewModel = FileSearchViewModel(
            searchService: InMemoryFileSearchService(items: [item]),
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            pasteboard: pasteboard
        )
        await viewModel.flushSearchForTesting()

        viewModel.perform(BuiltInCommandActionID.copyFilePath)
        await waitUntil { pasteboard.currentValue == item.url.path }

        #expect(pasteboard.currentValue == item.url.path)
        #expect(viewModel.statusMessage == "Path copied.")

        let missingAccess = FileSearchViewModel(
            searchService: MissingAccessFileSearchService(),
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            pasteboard: InMemoryPasteboard()
        )
        await missingAccess.flushSearchForTesting()
        #expect(missingAccess.loadState == .needsFolderAccess)
        #expect(missingAccess.footerActions.first?.id == BuiltInCommandActionID.settings)
    }

    @Test @MainActor func fileSearchActionsCardExecutesNativeAndNestedActions() async throws {
        let item = FileSearchItem(
            url: URL(fileURLWithPath: "/Users/test/Desktop/contacts.csv"),
            name: "contacts.csv",
            parentPath: "/Users/test/Desktop",
            kind: .file,
            contentTypeIdentifier: "public.comma-separated-values-text",
            contentTypeDescription: "CSV document"
        )
        let actions = InMemoryFileActionService(
            applicationOptions: [.init(id: "numbers", title: "Numbers")],
            sharingOptions: [.init(id: "airdrop", title: "AirDrop")],
            chosenDestination: URL(fileURLWithPath: "/Users/test/Documents")
        )
        let pasteboard = InMemoryPasteboard()
        let info = InMemoryFinderInfoPresenter()
        let viewModel = FileSearchViewModel(
            searchService: InMemoryFileSearchService(items: [item]),
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            fileActionService: actions,
            finderInfoPresenter: info,
            pasteboard: pasteboard
        )
        await viewModel.flushSearchForTesting()

        viewModel.presentActions(for: item.id)
        #expect(viewModel.showsActionPanel)
        #expect(viewModel.filteredActionPanelItems.contains { $0.id == BuiltInCommandActionID.shareFile })
        #expect(viewModel.filteredActionPanelItems.contains { $0.id == BuiltInCommandActionID.trashFile })

        viewModel.performPanelAction(BuiltInCommandActionID.openFileWith)
        await waitUntil { viewModel.filteredActionPanelItems.first?.title == "Numbers" }
        let openOption = try #require(viewModel.filteredActionPanelItems.first?.id)
        viewModel.performPanelAction(openOption)
        await waitUntil { actions.opened.count == 1 }
        #expect(actions.opened.first?.0 == item.url)
        #expect(actions.opened.first?.1 == "numbers")

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.shareFile)
        await waitUntil { viewModel.filteredActionPanelItems.first?.title == "AirDrop" }
        let shareOption = try #require(viewModel.filteredActionPanelItems.first?.id)
        viewModel.performPanelAction(shareOption)
        await waitUntil { actions.shared.count == 1 }
        #expect(actions.shared.first?.1 == "airdrop")

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.copyFile)
        await waitUntil { pasteboard.currentFileURLs == [item.url] }
        #expect(pasteboard.currentFileURLs == [item.url])

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.duplicateFile)
        await waitUntil { actions.duplicated == [item.url] }

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.showFileInfo)
        await waitUntil { info.infoPaths == [item.url.path] }

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.toggleFileDetails)
        #expect(viewModel.showsDetails == false)

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.copyFileTo)
        viewModel.performPanelAction(CommandActionID(rawValue: "file.destination.choose"))
        await waitUntil { actions.copied.count == 1 }
        #expect(actions.copied.first?.1 == URL(fileURLWithPath: "/Users/test/Documents"))

        viewModel.presentActions(for: item.id)
        viewModel.performPanelAction(BuiltInCommandActionID.trashFile)
        await waitUntil { actions.trashed == [item.url] }
        #expect(viewModel.results.isEmpty)
    }

    @Test func persistentFileIndexSearchesNamesContentsMetadataTagsAndCategories() async throws {
        let root = URL(fileURLWithPath: "/Users/test")
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlyTests-\(UUID().uuidString).sqlite")
        let database = FileIndexDatabase(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try await database.replaceAuthorizedScopes(with: [root.path])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            FileIndexRecord(
                path: "/Users/test/Desktop/wpb_hoa_contacts.csv",
                rootPath: root.path,
                name: "wpb_hoa_contacts.csv",
                parentPath: "/Users/test/Desktop",
                kind: .file,
                category: .documents,
                contentTypeIdentifier: "public.comma-separated-values-text",
                contentTypeDescription: "CSV document",
                byteCount: 200,
                createdAt: now,
                modifiedAt: now,
                lastUsedAt: now,
                tags: [],
                metadataText: "CSV spreadsheet",
                contentText: "",
                scanGeneration: 1
            ),
            FileIndexRecord(
                path: "/Users/test/Pictures/board-photo.png",
                rootPath: root.path,
                name: "board-photo.png",
                parentPath: "/Users/test/Pictures",
                kind: .file,
                category: .images,
                contentTypeIdentifier: "public.png",
                contentTypeDescription: "PNG image",
                byteCount: 500,
                createdAt: now,
                modifiedAt: now,
                lastUsedAt: nil,
                tags: ["HOA Board"],
                metadataText: "PNG image",
                contentText: "",
                scanGeneration: 1
            ),
            FileIndexRecord(
                path: "/Users/test/Documents/budget.pdf",
                rootPath: root.path,
                name: "budget.pdf",
                parentPath: "/Users/test/Documents",
                kind: .file,
                category: .documents,
                contentTypeIdentifier: "com.adobe.pdf",
                contentTypeDescription: "PDF document",
                byteCount: 800,
                createdAt: now,
                modifiedAt: now,
                lastUsedAt: nil,
                tags: [],
                metadataText: "Author Treasurer quarterly finance",
                contentText: "",
                scanGeneration: 1
            ),
            FileIndexRecord(
                path: "/Users/test/Documents/notes.txt",
                rootPath: root.path,
                name: "notes.txt",
                parentPath: "/Users/test/Documents",
                kind: .file,
                category: .documents,
                contentTypeIdentifier: "public.plain-text",
                contentTypeDescription: "Plain text",
                byteCount: 100,
                createdAt: now,
                modifiedAt: now,
                lastUsedAt: nil,
                tags: [],
                metadataText: "Plain text",
                contentText: "",
                scanGeneration: 1
            )
        ]
        try await database.upsert(records)
        try await database.updateContent([
            FileContentUpdate(
                path: "/Users/test/Documents/notes.txt",
                text: "homeowner association emergency contacts",
                metadata: "Plain text",
                tags: []
            )
        ])

        let names = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "wpb hoa", limit: 10),
            includesFileContents: false,
            includesMetadata: false,
            includesTags: false
        ))
        #expect(names.map(\.name) == ["wpb_hoa_contacts.csv"])

        let contents = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "emergency contacts", limit: 10),
            includesFileNames: false,
            includesFileContents: true,
            includesMetadata: false,
            includesTags: false
        ))
        #expect(contents.first?.name == "notes.txt")
        #expect(contents.first?.matchKind == .contents)

        let metadata = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "treasurer finance", limit: 10),
            includesFileNames: false,
            includesFileContents: false,
            includesMetadata: true,
            includesTags: false
        ))
        #expect(metadata.first?.name == "budget.pdf")
        #expect(metadata.first?.matchKind == .metadata)

        let tags = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "hoa board", limit: 10),
            category: .images,
            includesFileNames: false,
            includesFileContents: false,
            includesMetadata: false,
            includesTags: true
        ))
        #expect(tags.first?.name == "board-photo.png")
        #expect(tags.first?.tags == ["HOA Board"])
        #expect(tags.first?.matchKind == .tag)
    }

    @Test func fileIndexScannerFindsFilesImmediatelyAndRefreshesChangedContents() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlyScannerTests-\(UUID().uuidString)", isDirectory: true)
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = desktop.appendingPathComponent("wpb_hoa_contacts.csv")
        try Data("name,email\nPalm Beach HOA,first@example.com".utf8).write(to: target)
        let databaseURL = root
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent("index.sqlite")
        let database = FileIndexDatabase(databaseURL: databaseURL)
        let statusHub = FileIndexStatusHub()

        try await FileIndexScanner.scan(scopes: [desktop], database: database, statusHub: statusHub)

        let byName = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "wpb hoa contacts", limit: 10),
            includesFileContents: false,
            includesMetadata: false,
            includesTags: false
        ))
        #expect(byName.first?.url == target)

        let byContents = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "Palm Beach HOA", limit: 10),
            includesFileNames: false,
            includesFileContents: true,
            includesMetadata: false,
            includesTags: false
        ))
        #expect(byContents.first?.url == target)

        try Data("name,email\nWest Palm Board,updated@example.com".utf8).write(to: target)
        try await FileIndexScanner.scanChangedPath(
            target.path,
            scopes: [desktop],
            database: database,
            statusHub: statusHub
        )
        let refreshed = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "West Palm Board", limit: 10),
            includesFileNames: false,
            includesFileContents: true,
            includesMetadata: false,
            includesTags: false
        ))
        #expect(refreshed.first?.url == target)
    }

    @Test func fileIndexSearchStaysInteractiveWithTenThousandRecords() async throws {
        let root = URL(fileURLWithPath: "/Users/test")
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlyPerformanceTests-\(UUID().uuidString).sqlite")
        let database = FileIndexDatabase(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try await database.replaceAuthorizedScopes(with: [root.path])
        let records = (0..<10_000).map { index in
            let name = index == 7_777 ? "wpb_hoa_contacts.csv" : "document-\(index).txt"
            return FileIndexRecord(
                path: "/Users/test/Documents/\(name)",
                rootPath: root.path,
                name: name,
                parentPath: "/Users/test/Documents",
                kind: .file,
                category: .documents,
                contentTypeIdentifier: "public.plain-text",
                contentTypeDescription: "Plain text",
                byteCount: 100,
                createdAt: nil,
                modifiedAt: nil,
                lastUsedAt: nil,
                tags: [],
                metadataText: "Plain text",
                contentText: "",
                scanGeneration: 1
            )
        }
        let clock = ContinuousClock()
        let buildStarted = clock.now
        try await database.upsert(records)
        let buildElapsed = buildStarted.duration(to: clock.now)

        let started = clock.now
        let results = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "wpb hoa", limit: 100),
            includesFileContents: false,
            includesMetadata: false,
            includesTags: false
        ))
        let elapsed = started.duration(to: clock.now)

        #expect(results.first?.name == "wpb_hoa_contacts.csv")
        #expect(elapsed < .milliseconds(250))
        print(
            "FILE_INDEX_BENCHMARK records=10000 build_ms=\(milliseconds(buildElapsed)) " +
                "query_ms=\(milliseconds(elapsed))"
        )
    }

    @Test @MainActor func fileIndexChangeMonitorReceivesFileLevelEvents() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlyFSEventsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FileEventRecorder()
        let monitor = FileIndexChangeMonitor()
        monitor.start(paths: [root.path]) { paths in
            Task { await recorder.record(paths) }
        }
        defer { monitor.stop() }
        let changedFile = root.appendingPathComponent("changed.txt")
        try Data("changed".utf8).write(to: changedFile)

        await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            await recorder.contains(path: changedFile.path)
        }

        #expect(await recorder.contains(path: changedFile.path))
    }

    @Test func fileIndexNeverIndexesItsOwnDatabaseDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlySelfIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let visible = root.appendingPathComponent("Visible Notes.txt")
        try Data("searchable fixture".utf8).write(to: visible)
        let databaseURL = root
            .appendingPathComponent("Commandly Index", isDirectory: true)
            .appendingPathComponent("FileIndex.sqlite")
        let database = FileIndexDatabase(databaseURL: databaseURL)
        let statusHub = FileIndexStatusHub()

        try await FileIndexScanner.scan(scopes: [root], database: database, statusHub: statusHub)

        let visibleResults = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "Visible Notes", limit: 10),
            includesFileContents: false,
            includesMetadata: false,
            includesTags: false
        ))
        let selfResults = try await database.search(FileSearchRequest(
            query: SearchQuery(text: "FileIndex", limit: 10),
            includesFileContents: false,
            includesMetadata: false,
            includesTags: false
        ))
        #expect(visibleResults.first?.url == visible)
        #expect(selfResults.isEmpty)
        #expect(database.isStoragePath(databaseURL.path))
    }

    @Test @MainActor func csvPreviewParserHandlesQuotedCommasNewlinesAndEscapedQuotes() throws {
        let csv = "Name,Note,Phone\r\n"
            + "\"Garden, Lakes\",\"Line one\nLine two\",561-555-0100\r\n"
            + "Example,\"He said \"\"Hello\"\"\",561-555-0101\n"

        let preview = try CSVPreviewParser.parse(csv)

        #expect(preview.headers == ["Name", "Note", "Phone"])
        #expect(preview.rows == [
            ["Garden, Lakes", "Line one\nLine two", "561-555-0100"],
            ["Example", "He said \"Hello\"", "561-555-0101"]
        ])
        #expect(preview.isTruncated == false)
    }

    @Test @MainActor func csvPreviewParserBoundsLargeFiles() throws {
        let preview = try CSVPreviewParser.parse(
            "Name,Value\nFirst,1\nSecond,2\n",
            maximumRows: 1
        )

        #expect(preview.headers == ["Name", "Value"])
        #expect(preview.rows == [["First", "1"]])
        #expect(preview.isTruncated)
    }

    @Test @MainActor func launcherRootFooterExposesAppMenuAndActions() {
        let viewModel = LauncherViewModel()
        #expect(viewModel.route == .root)
        #expect(viewModel.appMenuActions.map(\.id) == [
            BuiltInCommandActionID.settings,
            BuiltInCommandActionID.quit
        ])
        #expect(viewModel.footerActions.map(\.id) == [
            BuiltInCommandActionID.openActions
        ])
        #expect(viewModel.rootActionsMenuItems.isEmpty)
    }

    @Test @MainActor func launcherRootFooterSettingsOpensSettingsAndDismisses() {
        var didDismiss = false
        var didOpenSettings = false
        let viewModel = LauncherViewModel(
            onDismiss: { didDismiss = true },
            onOpenSettings: { didOpenSettings = true }
        )

        viewModel.performFooterAction(BuiltInCommandActionID.settings)

        #expect(didDismiss)
        #expect(didOpenSettings)
    }

    @Test @MainActor func launcherRootFooterQuitInvokesQuitCallback() {
        var didQuit = false
        let viewModel = LauncherViewModel(onQuit: { didQuit = true })

        viewModel.performFooterAction(BuiltInCommandActionID.quit)

        #expect(didQuit)
    }

    @Test @MainActor func applicationActionsPanelExposesFullActionSet() async {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.demo",
            name: "Demo",
            path: "/Applications/Demo.app"
        )
        let prefs = InMemoryApplicationPreferencesStore()
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app]),
            applicationPreferencesStore: prefs
        )
        await viewModel.flushSearchForTesting()
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                path: app.path
            )
        ]
        viewModel.select("app:\(app.bundleIdentifier)")
        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)

        let ids = viewModel.filteredApplicationActions.map(\.id)
        #expect(ids.contains(BuiltInCommandActionID.openApplication))
        #expect(ids.contains(BuiltInCommandActionID.showInFinder))
        #expect(ids.contains(BuiltInCommandActionID.showInfoInFinder))
        #expect(ids.contains(BuiltInCommandActionID.showPackageContents))
        #expect(ids.contains(BuiltInCommandActionID.toggleFavorite))
        #expect(ids.contains(BuiltInCommandActionID.copyAppName))
        #expect(ids.contains(BuiltInCommandActionID.copyAppPath))
        #expect(ids.contains(BuiltInCommandActionID.copyBundleIdentifier))
        #expect(ids.contains(BuiltInCommandActionID.toggleAutoQuit))
        #expect(ids.contains(BuiltInCommandActionID.toggleDisableApplication))
        #expect(ids.contains(BuiltInCommandActionID.uninstallApplication))
        #expect(ids.contains(BuiltInCommandActionID.resetAppRanking))
    }

    @Test @MainActor func applicationActionsCopyNamePathAndBundleID() async {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.copy",
            name: "CopyApp",
            path: "/Applications/CopyApp.app"
        )
        let pasteboard = InMemoryPasteboard()
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app]),
            pasteboard: pasteboard
        )
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                path: app.path
            )
        ]
        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)

        viewModel.performApplicationAction(BuiltInCommandActionID.copyAppName)
        await waitUntil { pasteboard.currentValue == "CopyApp" }
        #expect(pasteboard.currentValue == "CopyApp")

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.copyAppPath)
        await waitUntil { pasteboard.currentValue == "/Applications/CopyApp.app" }
        #expect(pasteboard.currentValue == "/Applications/CopyApp.app")

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.copyBundleIdentifier)
        await waitUntil { pasteboard.currentValue == "com.example.copy" }
        #expect(pasteboard.currentValue == "com.example.copy")
    }

    @Test @MainActor func applicationActionsToggleFavoriteDisableAndReveal() async {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.fav",
            name: "FavApp",
            path: "/Applications/FavApp.app"
        )
        let prefs = InMemoryApplicationPreferencesStore()
        let revealer = InMemoryFileRevealer()
        let bundles = InMemoryApplicationBundleManager()
        let info = InMemoryFinderInfoPresenter()
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app]),
            applicationPreferencesStore: prefs,
            fileRevealer: revealer,
            bundleManager: bundles,
            finderInfoPresenter: info
        )
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                path: app.path
            )
        ]
        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)

        viewModel.performApplicationAction(BuiltInCommandActionID.toggleFavorite)
        await waitUntil { prefs.load().isFavorite(app.bundleIdentifier) }
        #expect(prefs.load().isFavorite(app.bundleIdentifier))

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.toggleAutoQuit)
        await waitUntil { prefs.load().isAutoQuitEnabled(app.bundleIdentifier) }
        #expect(prefs.load().isAutoQuitEnabled(app.bundleIdentifier))

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.showInFinder)
        await waitUntil { revealer.revealedURLs.isEmpty == false }
        #expect(revealer.revealedURLs.map(\.path).contains("/Applications/FavApp.app"))

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.showPackageContents)
        await waitUntil { bundles.packageContentPaths.isEmpty == false }
        #expect(bundles.packageContentPaths.contains("/Applications/FavApp.app"))

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.showInfoInFinder)
        await waitUntil { info.infoPaths.isEmpty == false }
        #expect(info.infoPaths.contains("/Applications/FavApp.app"))

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.toggleDisableApplication)
        await waitUntil { prefs.load().isDisabled(app.bundleIdentifier) }
        #expect(prefs.load().isDisabled(app.bundleIdentifier))
    }

    @Test @MainActor func applicationActionsUninstallOpensReviewAndTrashesSelection() async {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.trash",
            name: "TrashMe",
            path: "/Applications/TrashMe.app"
        )
        let related = [
            ApplicationRelatedItem(
                name: "TrashMe.app",
                containerPath: "/Applications",
                path: "/Applications/TrashMe.app",
                byteCount: 1_000,
                kind: .application
            ),
            ApplicationRelatedItem(
                name: "com.example.trash",
                containerPath: "~/Library/Caches",
                path: "/Users/test/Library/Caches/com.example.trash",
                byteCount: 200,
                kind: .folder
            )
        ]
        let prefs = InMemoryApplicationPreferencesStore(
            preferences: ApplicationPreferences(
                favoriteBundleIDs: ["com.example.trash"],
                disabledBundleIDs: [],
                autoQuitBundleIDs: [],
                ranking: ["com.example.trash": AppUsageRanking(openCount: 4, lastOpenedAt: Date())]
            )
        )
        let bundles = InMemoryApplicationBundleManager()
        let discoverer = InMemoryApplicationUninstallDiscoverer(
            itemsByBundleID: [app.bundleIdentifier: related]
        )
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app]),
            applicationPreferencesStore: prefs,
            bundleManager: bundles,
            uninstallDiscoverer: discoverer
        )
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                path: app.path
            )
        ]

        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.uninstallApplication)
        await waitUntil { viewModel.uninstallViewModel != nil }
        #expect(viewModel.route == .uninstallReview(bundleIdentifier: app.bundleIdentifier))

        guard let uninstall = viewModel.uninstallViewModel else {
            Issue.record("Expected uninstall view model")
            return
        }
        uninstall.load()
        await waitUntil { uninstall.isLoading == false }
        #expect(uninstall.items.count == 2)
        #expect(uninstall.selectedPaths.count == 2)

        uninstall.confirmUninstall()
        await waitUntil { viewModel.route == .root }
        #expect(bundles.trashedPaths.contains("/Applications/TrashMe.app"))
        #expect(bundles.trashedPaths.contains("/Users/test/Library/Caches/com.example.trash"))
        #expect(prefs.load().favoriteBundleIDs.contains(app.bundleIdentifier) == false)
        #expect(prefs.load().ranking[app.bundleIdentifier] == nil)
    }

    @Test @MainActor func uninstallDiscovererMatchesHelperBundlePrefixes() {
        let needles = WorkspaceApplicationUninstallDiscoverer.matchNeedles(
            bundleIdentifier: "com.openai.atlas",
            appName: "ChatGPT Atlas"
        )
        #expect(WorkspaceApplicationUninstallDiscoverer.name("com.openai.atlas", matchesNeedles: needles))
        #expect(WorkspaceApplicationUninstallDiscoverer.name("com.openai.atlas.local-agent-xpc-helper", matchesNeedles: needles))
        #expect(WorkspaceApplicationUninstallDiscoverer.name("com.openai.atlas.update-helper.plist", matchesNeedles: needles))
        #expect(WorkspaceApplicationUninstallDiscoverer.name("com.openai.atlas.binarycookies", matchesNeedles: needles))
        #expect(WorkspaceApplicationUninstallDiscoverer.name("com.openai.atlas.web.plist", matchesNeedles: needles))
        #expect(WorkspaceApplicationUninstallDiscoverer.name("ChatGPT Atlas", matchesNeedles: needles))
        #expect(WorkspaceApplicationUninstallDiscoverer.name("unrelated.app", matchesNeedles: needles) == false)
        #expect(WorkspaceApplicationUninstallDiscoverer.name("com.apple.Safari", matchesNeedles: needles) == false)
    }

    @Test @MainActor func applicationActionsResetRanking() async {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.rank",
            name: "RankMe",
            path: "/Applications/RankMe.app"
        )
        let prefs = InMemoryApplicationPreferencesStore(
            preferences: ApplicationPreferences(
                favoriteBundleIDs: [],
                disabledBundleIDs: [],
                autoQuitBundleIDs: [],
                ranking: ["com.example.rank": AppUsageRanking(openCount: 4, lastOpenedAt: Date())]
            )
        )
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app]),
            applicationPreferencesStore: prefs
        )
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                path: app.path
            )
        ]
        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        viewModel.performApplicationAction(BuiltInCommandActionID.resetAppRanking)
        await waitUntil { prefs.load().ranking[app.bundleIdentifier] == nil }
        #expect(prefs.load().ranking[app.bundleIdentifier] == nil)
    }

    @Test @MainActor func applicationSearchHidesDisabledAppsOnEmptyQuery() async {
        let apps = [
            InstalledApplication(bundleIdentifier: "com.example.a", name: "Alpha", path: "/A.app"),
            InstalledApplication(bundleIdentifier: "com.example.b", name: "Beta", path: "/B.app")
        ]
        let prefs = InMemoryApplicationPreferencesStore(
            preferences: ApplicationPreferences(
                favoriteBundleIDs: [],
                disabledBundleIDs: ["com.example.b"],
                autoQuitBundleIDs: [],
                ranking: [:]
            )
        )
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: apps),
            applicationPreferencesStore: prefs,
            placeholderItems: []
        )
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.contains { $0.id == "app:com.example.a" })
        #expect(viewModel.rootItems.contains { $0.id == "app:com.example.b" } == false)

        viewModel.query = "Beta"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.contains { $0.id == "app:com.example.b" })
        #expect(viewModel.rootItems.first { $0.id == "app:com.example.b" }?.badge == .disabled)
    }

    @Test @MainActor func autoQuitServiceTerminatesIdleListedApps() async {
        let prefs = InMemoryApplicationPreferencesStore(
            preferences: ApplicationPreferences(
                favoriteBundleIDs: [],
                disabledBundleIDs: [],
                autoQuitBundleIDs: ["com.example.idle"],
                ranking: [:]
            )
        )
        let running = InMemoryRunningApplicationController(
            frontmost: "com.apple.finder",
            running: [
                RunningApplicationSnapshot(bundleIdentifier: "com.example.idle", isActive: false),
                RunningApplicationSnapshot(bundleIdentifier: "com.apple.finder", isActive: true)
            ]
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let service = AutoQuitService(
            preferencesStore: prefs,
            runningApps: running,
            now: { now }
        )
        service.setLastActiveAtForTesting("com.example.idle", date: now.addingTimeInterval(-AutoQuitService.idleThreshold - 1))
        await service.evaluate()
        #expect(running.terminated.contains("com.example.idle"))
    }

    @Test @MainActor func launcherResetAfterDismissClearsClipboardSurface() {
        let store = ClipboardHistoryStore()
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: store
        )
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        #expect(viewModel.activeApplicationModel(as: ClipboardHistoryViewModel.self) != nil)

        viewModel.resetAfterDismiss()
        #expect(viewModel.route == .root)
        #expect(viewModel.activeApplication == nil)
        #expect(viewModel.query.isEmpty)
    }

    @Test @MainActor func launcherPrepareAndRequestSearchFocusBumpEpoch() {
        let viewModel = LauncherViewModel()
        let initial = viewModel.searchFocusEpoch

        viewModel.prepareForPresentation()
        #expect(viewModel.searchFocusEpoch == initial + 1)
        #expect(viewModel.query.isEmpty)

        viewModel.query = "partial"
        viewModel.requestSearchFocus()
        #expect(viewModel.searchFocusEpoch == initial + 2)
        // Focus reclaim alone must not wipe an in-progress query.
        #expect(viewModel.query == "partial")
    }

    @Test @MainActor func launcherGoBackRequestsSearchFocus() {
        let store = ClipboardHistoryStore()
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: store
        )
        viewModel.query = "clip"
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        let epochBeforeReturn = viewModel.searchFocusEpoch

        viewModel.goBack()
        #expect(viewModel.route == .root)
        #expect(viewModel.query.isEmpty)
        #expect(viewModel.searchFocusEpoch == epochBeforeReturn + 1)
    }

    @Test @MainActor func launcherEscapeFromApplicationReturnsHomeThenSignalsHide() async {
        var dismissed = false
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: ClipboardHistoryStore(),
            onDismiss: { dismissed = true }
        )
        viewModel.query = "clip"
        await viewModel.flushSearchForTesting()
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        #expect(viewModel.activeApplicationModel(as: ClipboardHistoryViewModel.self) != nil)

        #expect(viewModel.handleEscape())
        #expect(viewModel.route == .root)
        #expect(viewModel.activeApplication == nil)
        #expect(viewModel.query.isEmpty)
        #expect(dismissed == false)

        // Root Esc is not consumed by the view model; the window host hides.
        #expect(viewModel.handleEscape() == false)
        #expect(dismissed == false)
        viewModel.dismiss()
        #expect(dismissed)
    }

    @Test @MainActor func launcherEscapeClearsApplicationQueryBeforeReturningHome() async {
        let viewModel = LauncherViewModel(
            clipboardHistoryStore: ClipboardHistoryStore()
        )
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        let clipboard = viewModel.activeApplicationModel(as: ClipboardHistoryViewModel.self)
        #expect(clipboard != nil)
        clipboard?.query = "needle"

        #expect(viewModel.handleEscape())
        #expect(viewModel.route == .application(BuiltInCommandID.clipboardHistory))
        #expect(clipboard?.query.isEmpty == true)

        #expect(viewModel.handleEscape())
        #expect(viewModel.route == .root)
        #expect(viewModel.activeApplication == nil)
    }

    @Test @MainActor func launcherEscapeClosesApplicationActionsPanelBeforeGoingBack() {
        let app = InstalledApplication(
            bundleIdentifier: "com.example.app",
            name: "Example",
            path: "/Applications/Example.app"
        )
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: [app])
        )
        viewModel.cachedApplications = [
            InstalledApplicationSnapshot(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                path: app.path
            )
        ]
        viewModel.presentApplicationActions(forBundleID: app.bundleIdentifier)
        #expect(viewModel.showsApplicationActionsPanel)

        #expect(viewModel.handleEscape())
        #expect(viewModel.showsApplicationActionsPanel == false)
        #expect(viewModel.route == .root)
    }

    @Test @MainActor func launcherWindowChromeKeepsBorderlessKeyable() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        #expect(window.canBecomeKey == false)

        var needsCentering = true
        LauncherWindowConfigurator.applyChrome(to: window, centerIfNeeded: &needsCentering)
        #expect(window.styleMask.contains(.borderless))
        #expect(window.styleMask.contains(.titled) == false)
        #expect(window.canBecomeKey)
        #expect(needsCentering == false)

        // Second apply must not re-center, but must keep keyability + borderless chrome.
        LauncherWindowConfigurator.applyChrome(to: window, centerIfNeeded: &needsCentering)
        #expect(needsCentering == false)
        #expect(window.canBecomeKey)
        #expect(window.styleMask.contains(.borderless))
    }

    @Test @MainActor func launcherWindowEnsureKeyablePromotesBorderlessWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        #expect(window.canBecomeKey == false)
        LauncherWindowConfigurator.ensureKeyable(window)
        #expect(window.canBecomeKey)
        // Idempotent when already keyable.
        LauncherWindowConfigurator.ensureKeyable(window)
        #expect(window.canBecomeKey)
    }

    @Test @MainActor func appRuntimeShowLauncherRequestsSearchFocusAfterRaise() async {
        let container = makeTestContainer(hasCompletedOnboarding: true)
        let runtime = AppRuntime(container: container)
        runtime.showsOnboarding = false
        let viewModel = runtime.makeLauncherViewModel(onOpenSettings: {})
        let epochBefore = viewModel.searchFocusEpoch

        runtime.showLauncher()
        #expect(runtime.showsLauncher)
        // `requestSearchFocus` runs on the next main-queue turn after raise.
        await yieldMainQueue()
        #expect(viewModel.searchFocusEpoch == epochBefore + 1)
    }

    @Test @MainActor func appRuntimeHideLauncherClearsClipboardSurfaceObservation() {
        let container = makeTestContainer(hasCompletedOnboarding: true)
        let runtime = AppRuntime(container: container)
        runtime.showsOnboarding = false
        let viewModel = runtime.makeLauncherViewModel(onOpenSettings: {})
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        #expect(viewModel.activeApplicationModel(as: ClipboardHistoryViewModel.self) != nil)

        runtime.showLauncher()
        #expect(runtime.showsLauncher)
        runtime.hideLauncher()
        #expect(runtime.showsLauncher == false)
        #expect(viewModel.route == .root)
        #expect(viewModel.activeApplication == nil)
    }

    @Test @MainActor func clipboardHistoryStorePollDoesNotRequireUIActivation() {
        // Headless capture: poll mutates entries only. UI activation is owned by
        // explicit open paths; this guards the non-UI contract used by background monitoring.
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.headless.\(UUID().uuidString)"))
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("background-capture", forType: .string)
        store.poll()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.contentType == .text)
        store.poll()
        #expect(store.entries.count == 1)
    }

    @Test @MainActor func clipboardHistoryFiltersAndCopiesWithoutLoggingRequirement() {
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.filter.\(UUID().uuidString)"))
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        let entry = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            contentType: .text,
            preview: "Hello Commandly",
            text: "Hello Commandly",
            imageTIFFData: nil,
            fileURLs: [],
            sourceAppName: "Xcode",
            sourceBundleIdentifier: "com.apple.dt.Xcode"
        )
        store.replaceEntriesForTesting([entry])
        let viewModel = ClipboardHistoryViewModel(
            store: store,
            onGoBack: {},
            onDismiss: {}
        )
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.query = "commandly"
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.query = "zzznomatch"
        #expect(viewModel.filteredEntries.isEmpty)
        viewModel.query = "xcode"
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.query = ""
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.filter = .image
        #expect(viewModel.filteredEntries.isEmpty)
        viewModel.filter = .all
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.perform(BuiltInCommandActionID.copy)
        #expect(viewModel.statusMessage == nil)
        #expect(pasteboard.string(forType: .string) == "Hello Commandly")
    }

    @Test @MainActor func clipboardHistoryFiltersMatchSearchableTextAndLabels() {
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.enrichFilter.\(UUID().uuidString)"))
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        let imageEntry = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            contentType: .image,
            preview: "Image",
            text: nil,
            imageTIFFData: Data([0x00]),
            fileURLs: [],
            sourceAppName: "Preview",
            sourceBundleIdentifier: "com.apple.Preview",
            searchableText: "Invoice total due Friday",
            classificationLabels: ["Flower", "Plant"],
            enrichmentStatus: .ready
        )
        store.replaceEntriesForTesting([imageEntry])
        let viewModel = ClipboardHistoryViewModel(
            store: store,
            onGoBack: {},
            onDismiss: {}
        )

        viewModel.query = "invoice"
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.query = "flower"
        #expect(viewModel.filteredEntries.count == 1)
        viewModel.query = "nomatch-xyz"
        #expect(viewModel.filteredEntries.isEmpty)
        viewModel.query = ""
        viewModel.filter = .image
        #expect(viewModel.filteredEntries.count == 1)
    }

    @Test @MainActor func clipboardEnrichmentAppliesAndIgnoresStaleIDs() async {
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.enrichApply.\(UUID().uuidString)"))
        let stub = StubClipboardContentEnricher(
            result: .ready(searchableText: "OCR hello", labels: ["Document"])
        )
        let store = ClipboardHistoryStore(pasteboard: pasteboard, enricher: stub)
        let entryID = UUID()
        let entry = ClipboardHistoryEntry(
            id: entryID,
            createdAt: Date(),
            contentType: .image,
            preview: "Image",
            text: nil,
            imageTIFFData: Data([0x01, 0x02]),
            fileURLs: [],
            sourceAppName: nil,
            sourceBundleIdentifier: nil,
            enrichmentStatus: .pending
        )
        store.replaceEntriesForTesting([entry])
        store.enqueueEnrichmentForTesting(entry)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if store.entry(id: entryID)?.enrichmentStatus == .ready {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let enriched = store.entry(id: entryID)
        #expect(enriched?.enrichmentStatus == .ready)
        #expect(enriched?.searchableText == "OCR hello")
        #expect(enriched?.classificationLabels == ["Document"])

        store.applyEnrichment(
            id: UUID(),
            enrichment: .ready(searchableText: "stale", labels: ["Nope"])
        )
        #expect(store.entry(id: entryID)?.searchableText == "OCR hello")
    }

    @Test @MainActor func clipboardDeleteCancelsPendingEnrichment() async {
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.enrichCancel.\(UUID().uuidString)"))
        let stub = StubClipboardContentEnricher(
            result: .ready(searchableText: "should not apply", labels: ["X"]),
            delayNanoseconds: 300_000_000
        )
        let store = ClipboardHistoryStore(pasteboard: pasteboard, enricher: stub)
        let entryID = UUID()
        let entry = ClipboardHistoryEntry(
            id: entryID,
            createdAt: Date(),
            contentType: .image,
            preview: "Image",
            text: nil,
            imageTIFFData: Data([0x03]),
            fileURLs: [],
            sourceAppName: nil,
            sourceBundleIdentifier: nil,
            enrichmentStatus: .pending
        )
        store.replaceEntriesForTesting([entry])
        store.enqueueEnrichmentForTesting(entry)
        store.delete(id: entryID)

        try? await Task.sleep(for: .milliseconds(400))
        #expect(store.entry(id: entryID) == nil)
        #expect(store.entries.isEmpty)
    }

    @Test @MainActor func clipboardImageFileURLDetection() {
        #expect(ClipboardImageFile.isImageFileURL(URL(fileURLWithPath: "/tmp/photo.PNG")))
        #expect(ClipboardImageFile.isImageFileURL(URL(fileURLWithPath: "/tmp/shot.webp")))
        #expect(ClipboardImageFile.isImageFileURL(URL(fileURLWithPath: "/tmp/notes.txt")) == false)

        let entry = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            contentType: .fileURL,
            preview: "notes.txt, shot.jpg",
            text: nil,
            imageTIFFData: nil,
            fileURLs: [
                URL(fileURLWithPath: "/tmp/notes.txt"),
                URL(fileURLWithPath: "/tmp/shot.jpg")
            ],
            sourceAppName: nil,
            sourceBundleIdentifier: nil
        )
        #expect(entry.firstImageFileURL?.lastPathComponent == "shot.jpg")
    }

    @Test @MainActor func clipboardCopyToPasteboardDoesNotAppendHistoryEntry() {
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.suppress.\(UUID().uuidString)"))
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        let entry = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            contentType: .text,
            preview: "Re-copy me",
            text: "Re-copy me",
            imageTIFFData: nil,
            fileURLs: [],
            sourceAppName: "Commandly",
            sourceBundleIdentifier: "app.commandly"
        )
        store.replaceEntriesForTesting([entry])
        let countBefore = store.entries.count

        store.copyToPasteboard(entry)
        store.poll()
        store.poll()

        #expect(store.entries.count == countBefore)
        #expect(store.entries.first?.id == entry.id)
    }

    @Test @MainActor func clipboardHistoryCopyEntryUsesSpecificRow() {
        let pasteboard = NSPasteboard(name: .init("CommandlyTests.clipboard.rowCopy.\(UUID().uuidString)"))
        let store = ClipboardHistoryStore(pasteboard: pasteboard)
        let first = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            contentType: .text,
            preview: "First",
            text: "First",
            imageTIFFData: nil,
            fileURLs: [],
            sourceAppName: nil,
            sourceBundleIdentifier: nil
        )
        let second = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-60),
            contentType: .text,
            preview: "Second",
            text: "Second",
            imageTIFFData: nil,
            fileURLs: [],
            sourceAppName: nil,
            sourceBundleIdentifier: nil
        )
        store.replaceEntriesForTesting([first, second])
        let viewModel = ClipboardHistoryViewModel(
            store: store,
            onGoBack: {},
            onDismiss: {}
        )
        viewModel.select(first.id)
        viewModel.copyEntry(second)
        #expect(viewModel.statusMessage == nil)
        #expect(pasteboard.string(forType: .string) == "Second")
        #expect(store.entries.count == 2)
        store.poll()
        #expect(store.entries.count == 2)
    }

    @Test @MainActor func launcherViewModelFiltersAndSelectsPlaceholders() async {
        let viewModel = LauncherViewModel()
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.isEmpty == false)
        #expect(viewModel.selectedItem != nil)

        viewModel.query = "settings"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.contains { $0.id == BuiltInCommandID.openSettings.rawValue })
        #expect(viewModel.rootItems.allSatisfy { $0.matches(query: "settings") })

        viewModel.moveSelection(offset: 1)
        #expect(viewModel.selectedItem != nil)

        viewModel.query = "zzznomatch"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.isEmpty)
        #expect(viewModel.selectedID == nil)
    }

    @Test @MainActor func launcherSuppressesPointerHoverWhileResultsScrolling() async {
        let viewModel = LauncherViewModel()
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.count >= 3)

        let firstID = viewModel.rootItems[0].id
        let secondID = viewModel.rootItems[1].id
        let thirdID = viewModel.rootItems[2].id
        viewModel.select(firstID)

        viewModel.setHovered(secondID)
        #expect(viewModel.selectedID == secondID)

        viewModel.beginResultsScrolling()
        #expect(viewModel.isResultsScrolling)
        viewModel.setHovered(thirdID)
        #expect(viewModel.selectedID == secondID)

        viewModel.moveSelection(offset: -1)
        #expect(viewModel.selectedID == firstID)
        #expect(viewModel.isResultsScrolling)

        viewModel.flushResultsScrollingForTesting()
        #expect(viewModel.isResultsScrolling == false)
        #expect(viewModel.selectedID == firstID)

        viewModel.setHovered(thirdID)
        viewModel.beginPointerInput()
        #expect(viewModel.selectedID == thirdID)

        viewModel.beginResultsScrolling()
        viewModel.setHovered(secondID)
        #expect(viewModel.selectedID == thirdID)
        viewModel.flushResultsScrollingForTesting()
        #expect(viewModel.selectedID == secondID)
    }

    @Test @MainActor func launcherOpenSettingsActionInvokesCallback() async {
        var openedSettings = false
        var dismissed = false
        let viewModel = LauncherViewModel(
            onDismiss: { dismissed = true },
            onOpenSettings: { openedSettings = true }
        )
        viewModel.query = "Open Settings"
        await viewModel.flushSearchForTesting()
        viewModel.selectedID = BuiltInCommandID.openSettings.rawValue
        viewModel.confirmSelection()
        #expect(dismissed)
        #expect(openedSettings)
    }

    @Test @MainActor func launcherPlaceholderActionSurfacesHonestStatus() async {
        let viewModel = LauncherViewModel()
        await viewModel.flushSearchForTesting()
        viewModel.selectedID = "my-schedule"
        viewModel.confirmSelection()
        #expect(viewModel.statusMessage?.contains("not implemented") == true)
    }

    @Test @MainActor func launcherSearchRanksCommandsAndAppsWithAutocomplete() async {
        let apps = [
            InstalledApplication(bundleIdentifier: "com.example.alpha", name: "Alpha Editor", path: "/Applications/Alpha.app"),
            InstalledApplication(bundleIdentifier: "com.example.beta", name: "Beta Tools", path: "/Applications/Beta.app")
        ]
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: apps)
        )
        viewModel.query = "clip"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.first?.id == BuiltInCommandID.clipboardHistory.rawValue)
        #expect(viewModel.autocompleteSuffix.lowercased().hasPrefix("board") || viewModel.rootItems.first?.title == "Clipboard History")

        viewModel.query = "Alpha"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.contains {
            $0.action == .openInstalledApplication(bundleIdentifier: "com.example.alpha")
        })
        #expect(viewModel.rootItems.contains {
            if case .application(let path) = $0.icon {
                return path == "/Applications/Alpha.app"
            }
            return false
        })
        #expect(viewModel.autocompleteSuffix.isEmpty || viewModel.rootItems.contains { $0.title.hasPrefix("Alpha") })

        viewModel.acceptAutocomplete()
        await viewModel.flushSearchForTesting()
    }

    @Test @MainActor func launcherListsAllAppsBelowCommandsSection() async {
        let apps = (1...20).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.app\(index)",
                name: String(format: "App %02d", index),
                path: "/Applications/App\(index).app"
            )
        }
        let viewModel = LauncherViewModel(
            applicationQuery: InMemoryInstalledApplicationQuery(applications: apps)
        )
        await viewModel.flushSearchForTesting()

        let kinds = viewModel.sections.map(\.kind)
        if let commandsIndex = kinds.firstIndex(of: .commands),
           let applicationsIndex = kinds.firstIndex(of: .applications) {
            #expect(applicationsIndex > commandsIndex)
        } else {
            #expect(kinds.contains(.applications))
        }

        let applicationItems = viewModel.rootItems.filter { $0.section == .applications }
        #expect(applicationItems.count == 20)
    }

    @Test @MainActor func launcherCalculatorPinsAboveCommandsAndCopiesWithoutDismiss() async {
        let pasteboard = InMemoryPasteboard()
        var dismissed = false
        let viewModel = LauncherViewModel(
            pasteboard: pasteboard,
            onDismiss: { dismissed = true }
        )
        viewModel.query = "2 + 2"
        await viewModel.flushSearchForTesting()

        #expect(viewModel.sections.first?.kind == .calculator)
        #expect(viewModel.rootItems.first?.badge == .calculator)
        #expect(viewModel.rootItems.first?.title.contains("4") == true)
        #expect(viewModel.activeCalculatorResult != nil)

        await viewModel.confirmSelectionAndWaitForTesting()
        #expect(pasteboard.currentValue?.contains("4") == true)
        #expect(dismissed == false)
        #expect(viewModel.statusMessage == "Copied answer.")
    }

    @Test @MainActor func launcherCalculatorPreviewsIncompleteInputAndAcceptsTabCompletion() async {
        let viewModel = LauncherViewModel()
        viewModel.query = "sqrt(5"
        await viewModel.flushSearchForTesting()

        #expect(viewModel.sections.first?.kind == .calculator)
        #expect(viewModel.rootItems.first?.title.isEmpty == false)
        #expect(viewModel.autocompleteSuffix == ")")
        #expect(viewModel.autocompleteCompletion == "sqrt(5)")
        #expect(viewModel.autocompleteActionLabel == "Tab to complete")

        viewModel.acceptAutocomplete()
        #expect(viewModel.query == "sqrt(5)")
    }

    @Test @MainActor func launcherCalculatorReplacesConversionSuggestionAsQueryChanges() async {
        let viewModel = LauncherViewModel()
        viewModel.query = "5 mph"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.activeCalculatorResult?.formattedPrimaryValue.contains("km/h") == true)
        #expect(viewModel.autocompleteCompletion == "5 mph in km/h")
        #expect(viewModel.autocompleteActionLabel == "Tab to convert")

        viewModel.query = "5 mph in m"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.autocompleteCompletion == "5 mph in m/s")
    }

    @Test @MainActor func launcherCalculatorCanAcceptFuzzyReplacementWithoutSuffix() async {
        let viewModel = LauncherViewModel()
        viewModel.query = "sqart(25"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.autocompleteSuffix.isEmpty)
        #expect(viewModel.autocompleteCompletion == "sqrt(25)")

        viewModel.acceptAutocomplete()
        #expect(viewModel.query == "sqrt(25)")
    }

    @Test @MainActor func launcherCalculatorQuestionCanReturnToSearchForEditing() async {
        let viewModel = LauncherViewModel()
        viewModel.query = "ten plus ten"
        await viewModel.flushSearchForTesting()
        guard let result = viewModel.activeCalculatorResult else {
            Issue.record("Expected calculator result")
            return
        }
        let previousFocusEpoch = viewModel.searchFocusEpoch
        viewModel.editCalculatorQuestion(resultID: result.id.rawValue)
        #expect(viewModel.query == "ten plus ten")
        #expect(viewModel.searchFocusEpoch == previousFocusEpoch + 1)
    }

    @Test @MainActor func launcherCalculatorMenuProvidesContextualActions() async {
        let viewModel = LauncherViewModel()
        viewModel.query = "2 + 2"
        await viewModel.flushSearchForTesting()
        let ids = Set(viewModel.menuActions.map(\.id.rawValue))
        #expect(ids.contains("copyAnswer"))
        #expect(ids.contains("copyUnformatted"))
        #expect(ids.contains("openCalculator"))
        #expect(ids.contains("addToNote"))
        #expect(ids.contains("insertResult"))
        #expect(ids.contains("copyExpression"))
    }

    @Test @MainActor func launcherCalculatorDoesNotTriggerForAppNames() async {
        let viewModel = LauncherViewModel()
        viewModel.query = "Photoshop 2026"
        await viewModel.flushSearchForTesting()
        #expect(viewModel.rootItems.contains { $0.section == .calculator } == false)
    }

    @Test @MainActor func launcherOpensApplicationViaOpener() async {
        final class Recorder: ApplicationOpening, @unchecked Sendable {
            private(set) var opened: String?
            private var continuation: CheckedContinuation<Void, Never>?

            func openApplication(bundleIdentifier: String) async throws {
                opened = bundleIdentifier
                continuation?.resume()
                continuation = nil
            }

            func waitUntilOpened() async {
                if opened != nil { return }
                await withCheckedContinuation { continuation = $0 }
            }
        }
        let recorder = Recorder()
        var dismissed = false
        let viewModel = LauncherViewModel(
            applicationOpener: recorder,
            applicationQuery: InMemoryInstalledApplicationQuery(
                applications: [
                    InstalledApplication(bundleIdentifier: "com.example.app", name: "Example", path: "/Applications/Example.app")
                ]
            ),
            onDismiss: { dismissed = true }
        )
        viewModel.query = "Example"
        await viewModel.flushSearchForTesting()
        viewModel.selectedID = "app:com.example.app"
        viewModel.confirmSelection()
        await recorder.waitUntilOpened()
        #expect(recorder.opened == "com.example.app")
        // `dismiss()` runs on the MainActor after `openApplication` returns; yield so
        // the confirming task can finish before we assert.
        await yieldMainQueue()
        #expect(dismissed)
    }

    @Test @MainActor func compositeSearchServiceMergesAndSortsByScore() async throws {
        struct StubProvider: SearchProviding {
            let id: SearchProviderID
            let items: [SearchItem]
            func search(_ query: SearchQuery) async throws -> SearchResult {
                SearchResult(query: query, items: items)
            }
        }
        let service = CompositeSearchService(
            providers: [
                StubProvider(
                    id: SearchProviderID(rawValue: "a"),
                    items: [
                        SearchItem(id: "1", title: "Low", providerID: SearchProviderID(rawValue: "a"), score: 0.2)
                    ]
                ),
                StubProvider(
                    id: SearchProviderID(rawValue: "b"),
                    items: [
                        SearchItem(id: "2", title: "High", providerID: SearchProviderID(rawValue: "b"), score: 0.9)
                    ]
                )
            ]
        )
        let result = try await service.search(SearchQuery(text: "x", limit: 10))
        #expect(result.items.map(\.id) == ["2", "1"])
    }

    @Test @MainActor func appRuntimeToggleLauncherRespectsOnboardingGate() {
        let container = makeTestContainer(hasCompletedOnboarding: false)
        let runtime = AppRuntime(container: container)
        #expect(runtime.showsOnboarding)
        runtime.showLauncher()
        #expect(runtime.showsLauncher == false)

        runtime.showsOnboarding = false
        runtime.showLauncher()
        #expect(runtime.showsLauncher)
        runtime.toggleLauncher()
        #expect(runtime.showsLauncher == false)
    }

    @Test @MainActor func appRuntimeRestartOnboardingResetsProgress() async {
        let store = InMemoryOnboardingStatusStore(hasCompletedOnboarding: true)
        let settings = InMemoryAppSettingsStore(
            settings: AppSettings(
                opensAtLogin: true,
                prefersCommandlyEmojiPicker: true,
                hasConfirmedOptionSpaceHotkey: true,
                showMenuBarIcon: true,
                appearance: .dark,
                textSize: .larger,
                viewMode: .compact
            )
        )
        let folderAccess = InMemoryFolderAccessStore(bookmarkData: [Data([0x01])], forceUsable: true)
        let container = makeTestContainer(
            hasCompletedOnboarding: true,
            onboardingStatusStore: store,
            appSettingsStore: settings,
            folderAccessStore: folderAccess
        )
        let runtime = AppRuntime(container: container)
        #expect(runtime.showsOnboarding == false)

        _ = runtime.makeOnboardingViewModel()
        runtime.restartOnboarding()

        #expect(store.hasCompletedOnboarding == false)
        #expect(settings.load() == .default)
        #expect(folderAccess.bookmarkData.isEmpty)
        #expect(runtime.showsOnboarding)
        #expect(runtime.textSize == .standard)
        #expect(runtime.viewMode == .comfortable)
        #expect(container.appState.route == .onboarding)

        let restarted = runtime.makeOnboardingViewModel()
        #expect(restarted.step == .welcome)
    }

    @Test @MainActor func appDelegateKeepsRunningAfterWindowsClose() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
    }

    @Test @MainActor func folderAccessStoreRejectsLegacyBookmarksUntilTheyAreRegranted() {
        let suiteName = "CommandlyTests.FolderAccess.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bookmark = Data([0x01, 0x02, 0x03])
        defaults.set([bookmark], forKey: "settings.folderAccessBookmarks")
        let store = UserDefaultsFolderAccessStore(defaults: defaults)

        #expect(store.bookmarkData.isEmpty)

        store.saveBookmarks([bookmark])
        #expect(store.bookmarkData == [bookmark])
        #expect(defaults.integer(forKey: "settings.folderAccessBookmarkFormatVersion") == 1)
    }

    @Test @MainActor func setupTogglesPersistPreferences() async {
        let settings = InMemoryAppSettingsStore()
        let loginItems = InMemoryLoginItemManager()
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: settings,
            loginItemManager: loginItems,
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .preferences
        )

        viewModel.setPrefersCommandlyEmojiPicker(true)
        #expect(settings.load().prefersCommandlyEmojiPicker)

        viewModel.setOpensAtLogin(true)
        await waitUntil {
            await loginItems.status() == .enabled && settings.load().opensAtLogin
        }

        #expect(viewModel.opensAtLogin)
        #expect(settings.load().opensAtLogin)
        #expect(await loginItems.status() == .enabled)

        viewModel.setOpensAtLogin(false)
        await waitUntil {
            await loginItems.status() == .disabled && settings.load().opensAtLogin == false
        }

        #expect(viewModel.opensAtLogin == false)
        #expect(settings.load().opensAtLogin == false)
        #expect(await loginItems.status() == .disabled)
    }

    @Test @MainActor func openAtLoginFailureRevertsPreference() async {
        let settings = InMemoryAppSettingsStore()
        let loginItems = InMemoryLoginItemManager(shouldFail: true)
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: settings,
            loginItemManager: loginItems,
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .preferences
        )

        viewModel.setOpensAtLogin(true)
        await waitUntil {
            viewModel.loginItemErrorMessage != nil
        }

        #expect(viewModel.opensAtLogin == false)
        #expect(settings.load().opensAtLogin == false)
        #expect(viewModel.loginItemErrorMessage != nil)
    }

    @Test @MainActor func permissionGrantUpdatesStatus() async {
        let permissions = InMemoryPermissionService()
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: permissions,
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            initialStep: .permissions
        )

        await viewModel.preparePermissionsStep()
        #expect(viewModel.status(for: .filesAndFolders).state == .notDetermined)

        viewModel.handlePermissionAction(.filesAndFolders)
        await waitUntil {
            viewModel.status(for: .filesAndFolders).state == .authorized
        }

        #expect(viewModel.status(for: .filesAndFolders).state == .authorized)
        #expect(await permissions.state(for: .files) == .authorized)
    }

    @Test @MainActor func deniedPermissionOpensSettingsRecovery() async {
        let permissions = InMemoryPermissionService(states: [.accessibility: .denied])
        let opener = RecordingPrivacySettingsOpener()
        let viewModel = OnboardingViewModel(
            statusStore: InMemoryOnboardingStatusStore(),
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: permissions,
            privacySettingsOpener: opener,
            initialStep: .permissions
        )

        await viewModel.preparePermissionsStep()
        #expect(viewModel.status(for: .accessibility).state == .denied)

        viewModel.handlePermissionAction(.accessibility)
        await waitUntil {
            opener.openedPanes.contains(.accessibility)
        }

        #expect(opener.openedPanes == [.accessibility])
    }

    @MainActor
    private func makeTestContainer(
        hasCompletedOnboarding: Bool,
        onboardingStatusStore: InMemoryOnboardingStatusStore? = nil,
        appSettingsStore: InMemoryAppSettingsStore? = nil,
        folderAccessStore: InMemoryFolderAccessStore? = nil
    ) -> AppContainer {
        let store = onboardingStatusStore
            ?? InMemoryOnboardingStatusStore(hasCompletedOnboarding: hasCompletedOnboarding)
        let metadata = ApplicationMetadata(
            name: "Commandly",
            version: "1.0",
            build: "1",
            bundleIdentifier: "com.businessmate360.Commandly",
            environment: .testing
        )
        let fixedUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")
            ?? UUID()
        let dependencies = AppDependencies(
            metadata: metadata,
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 1_700_000_000)),
            uuidProvider: FixedUUIDProvider(uuid: fixedUUID),
            commandRegistry: CommandRegistry(),
            persistenceStore: InMemoryPersistenceStore(),
            permissionService: InMemoryPermissionService(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener(),
            onboardingStatusStore: store,
            appSettingsStore: appSettingsStore ?? InMemoryAppSettingsStore(),
            launcherApplicationPreferencesStore: InMemoryLauncherApplicationPreferencesStore(),
            applicationPreferencesStore: InMemoryApplicationPreferencesStore(),
            folderAccessStore: folderAccessStore ?? InMemoryFolderAccessStore(),
            loginItemManager: InMemoryLoginItemManager(),
            logger: Loggers.application
        )
        return AppContainer(dependencies: dependencies)
    }

    @MainActor
    private func yieldMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async {
        let started = ContinuousClock.now
        while ContinuousClock.now - started < .nanoseconds(timeoutNanoseconds) {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private nonisolated func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f", value)
    }
}

/// Test double that records privacy pane open requests.
private final class RecordingPrivacySettingsOpener: PrivacySettingsOpening, @unchecked Sendable {
    private(set) var openedPanes: [PrivacySettingsPane] = []

    func open(_ pane: PrivacySettingsPane) async {
        openedPanes.append(pane)
    }
}

private struct MissingAccessFileSearchService: FileSearching {
    func search(_ request: FileSearchRequest) async throws -> [FileSearchItem] {
        _ = request
        throw FileSearchError.noAuthorizedScopes
    }
}

private actor FileEventRecorder {
    private var paths: Set<String> = []

    func record(_ newPaths: [String]) {
        paths.formUnion(newPaths)
    }

    func contains(path: String) -> Bool {
        paths.contains(path)
    }
}

@MainActor
private struct TestLauncherApplication: LauncherApplication {
    static let id = CommandID(rawValue: "test.application")
    static let primaryActionID = CommandActionID(rawValue: "test.primary")
    let parentID: CommandID?

    init(parentID: CommandID? = nil) {
        self.parentID = parentID
    }

    let manifest = CommandManifest(
        id: id,
        title: "Test Application",
        subtitle: "Exercises dynamic application registration",
        systemImage: "testtube.2",
        category: .productivity,
        mode: .view,
        keywords: ["test"],
        defaultActions: [
            CommandActionDescriptor(
                id: primaryActionID,
                title: "Run",
                isPrimary: true
            )
        ]
    )

    var definition: LauncherApplicationDefinition {
        LauncherApplicationDefinition(
            manifest: manifest,
            parentID: parentID,
            kind: .application,
            order: 0
        )
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = TestLauncherApplicationModel()
        return .present(
            LauncherApplicationSession(manifest: manifest, model: model) { _ in
                EmptyView()
            }
        )
    }
}

@MainActor
private final class TestLauncherApplicationModel: LauncherApplicationModel {
    var statusMessage: String?
    var footerActions = TestLauncherApplication().manifest.defaultActions
    var menuActions: [CommandActionDescriptor] = []
    var showsActionsMenu = false

    func moveSelection(offset: Int) {
        _ = offset
    }

    func perform(_ actionID: CommandActionID) {
        statusMessage = actionID == TestLauncherApplication.primaryActionID ? "Ran" : nil
    }
}
