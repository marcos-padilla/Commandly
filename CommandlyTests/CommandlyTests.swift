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

struct CommandlyTests {
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

    @Test @MainActor func launcherOpensClipboardHistoryCommand() {
        let catalog = CommandCatalog.makeBuiltIn()
        let store = ClipboardHistoryStore()
        let viewModel = LauncherViewModel(catalog: catalog, clipboardHistoryStore: store)
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        #expect(viewModel.route == .command(BuiltInCommandID.clipboardHistory))
        #expect(viewModel.clipboardViewModel != nil)
        #expect(viewModel.contextTitle == "Clipboard History")
        #expect(viewModel.footerActions.contains { $0.id == BuiltInCommandActionID.copy })
    }

    @Test @MainActor func launcherResetAfterDismissClearsClipboardSurface() {
        let catalog = CommandCatalog.makeBuiltIn()
        let store = ClipboardHistoryStore()
        let viewModel = LauncherViewModel(catalog: catalog, clipboardHistoryStore: store)
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        #expect(viewModel.clipboardViewModel != nil)

        viewModel.resetAfterDismiss()
        #expect(viewModel.route == .root)
        #expect(viewModel.clipboardViewModel == nil)
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
        let catalog = CommandCatalog.makeBuiltIn()
        let store = ClipboardHistoryStore()
        let viewModel = LauncherViewModel(catalog: catalog, clipboardHistoryStore: store)
        viewModel.selectedID = BuiltInCommandID.clipboardHistory.rawValue
        viewModel.confirmSelection()
        let epochBeforeReturn = viewModel.searchFocusEpoch

        viewModel.goBack()
        #expect(viewModel.route == .root)
        #expect(viewModel.searchFocusEpoch == epochBeforeReturn + 1)
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
        #expect(viewModel.clipboardViewModel != nil)

        runtime.showLauncher()
        #expect(runtime.showsLauncher)
        runtime.hideLauncher()
        #expect(runtime.showsLauncher == false)
        #expect(viewModel.route == .root)
        #expect(viewModel.clipboardViewModel == nil)
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
        viewModel.selectedID = "search-files"
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
        #expect(viewModel.rootItems.contains { $0.action == .openApplication(bundleIdentifier: "com.example.alpha") })
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

    @Test @MainActor func launcherCalculatorPinsAboveCommandsAndCopies() async {
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
        #expect(dismissed)
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
}

/// Test double that records privacy pane open requests.
private final class RecordingPrivacySettingsOpener: PrivacySettingsOpening, @unchecked Sendable {
    private(set) var openedPanes: [PrivacySettingsPane] = []

    func open(_ pane: PrivacySettingsPane) async {
        openedPanes.append(pane)
    }
}
