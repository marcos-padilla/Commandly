import CommandKit
import Foundation
import SecurityKit
import Testing
@testable import Commandly

@Suite("Window Switcher application")
@MainActor
struct WindowSwitcherApplicationTests {
    @Test func sandboxedCompositionCanOmitTheUnavailableRuntime() {
        let registry = LauncherApplicationRegistry.makeBuiltIn(includesWindowSwitcher: false)

        #expect(registry.definition(for: WindowSwitcherApplication.applicationID) == nil)
        #expect(registry.isEffectivelyEnabled(WindowSwitcherApplication.applicationID) == false)
    }

    @Test func schemaResolvesTypedDefaultsAndDeclaresGenericSections() throws {
        let presenter = RecordingWindowSwitcherPresenter()
        let application = WindowSwitcherApplication(
            services: WindowSwitcherApplicationServices(presenter: presenter)
        )
        let registry = LauncherApplicationRegistry()
        try registry.register(BuiltInLauncherApplicationGroup.catalog)
        try registry.register(application)

        let definition = try #require(
            registry.definition(for: WindowSwitcherApplication.applicationID)
        )
        let settings = try #require(registry.resolvedSettings(for: definition.id))

        #expect(WindowSwitcherConfiguration(settings: settings) == .default)
        #expect(definition.configurationFields.count == 28)
        #expect(definition.configurationFields.allSatisfy { $0.section?.isEmpty == false })
        #expect(Set(definition.configurationFields.compactMap(\.section)).count == 9)
        #expect(definition.documentation != nil)
        #expect(definition.commandManifest?.mode == .action)
        #expect(
            definition.commandManifest?.availabilityRequirements == [
                .permission(identifier: PermissionKind.accessibility.rawValue),
            ]
        )
    }

    @Test func resolvedSettingsParseSelectionsBoundsAndExclusionTerms() {
        let settings = LauncherApplicationResolvedSettings(
            alias: "",
            hotKey: nil,
            isEnabled: true,
            configuration: [
                "shortcutMode": .text(WindowSwitcherShortcutMode.holdToCycle.rawValue),
                "filterMode": .text(WindowSwitcherFilterMode.activeApplication.rawValue),
                "sortOrder": .text(WindowSwitcherSortOrder.windowTitle.rawValue),
                "currentDesktopOnly": .boolean(false),
                "currentDisplayOnly": .boolean(true),
                "includeHiddenApplications": .boolean(true),
                "includeMinimizedWindows": .boolean(false),
                "includeWindowlessApplications": .boolean(true),
                "searchEnabled": .boolean(false),
                "mouseSelectionEnabled": .boolean(false),
                "vimNavigationEnabled": .boolean(true),
                "layoutStyle": .text(WindowSwitcherLayoutStyle.strip.rawValue),
                "itemSize": .text(WindowSwitcherItemSize.large.rawValue),
                "gridColumnCount": .integer(99),
                "showWindowTitles": .boolean(false),
                "showApplicationNames": .boolean(false),
                "showWindowActions": .boolean(false),
                "showThumbnails": .boolean(false),
                "livePreviewsEnabled": .boolean(false),
                "thumbnailCacheLimit": .integer(-1),
                "thumbnailQuality": .text(WindowSwitcherThumbnailQuality.detailed.rawValue),
                "placement": .text(WindowSwitcherPlacement.pointerDisplay.rawValue),
                "horizontalOffset": .integer(-900),
                "verticalOffset": .integer(900),
                "dockPreviewsEnabled": .boolean(true),
                "dockPreviewDelay": .decimal(8),
                "replaceCommandTab": .boolean(true),
                "exclusionTerms": .text("Mail, com.example.Editor\nmail\n  Notes  "),
            ]
        )

        let configuration = WindowSwitcherConfiguration(settings: settings)

        #expect(configuration.shortcutMode == .holdToCycle)
        #expect(configuration.filterMode == .activeApplication)
        #expect(configuration.sortOrder == .windowTitle)
        #expect(configuration.limitsToCurrentDesktop == false)
        #expect(configuration.limitsToCurrentDisplay)
        #expect(configuration.includesHiddenApplications)
        #expect(configuration.includesMinimizedWindows == false)
        #expect(configuration.includesWindowlessApplications)
        #expect(configuration.allowsSearch == false)
        #expect(configuration.allowsMouseSelection == false)
        #expect(configuration.allowsVimNavigation)
        #expect(configuration.layoutStyle == .strip)
        #expect(configuration.itemSize == .large)
        #expect(configuration.gridColumnCount == 8)
        #expect(configuration.showsWindowTitles == false)
        #expect(configuration.showsApplicationNames == false)
        #expect(configuration.showsWindowActions == false)
        #expect(configuration.showsThumbnails == false)
        #expect(configuration.usesLivePreviews == false)
        #expect(configuration.thumbnailCacheLimit == 0)
        #expect(configuration.thumbnailQuality == .detailed)
        #expect(configuration.placement == .pointerDisplay)
        #expect(configuration.horizontalOffset == -600)
        #expect(configuration.verticalOffset == 600)
        #expect(configuration.showsDockPreviews)
        #expect(configuration.dockPreviewDelay == 3)
        #expect(configuration.replacesCommandTab)
        #expect(configuration.exclusionTerms == ["Mail", "com.example.Editor", "Notes"])
    }

    @Test func numericSchemaIncludesNativeControlBounds() throws {
        let gridColumns = try #require(
            WindowSwitcherConfiguration.schema.first { $0.variable == "gridColumnCount" }
        )
        let previewDelay = try #require(
            WindowSwitcherConfiguration.schema.first { $0.variable == "dockPreviewDelay" }
        )

        #expect(gridColumns.kind == .integer)
        #expect(gridColumns.minimumValue == 2)
        #expect(gridColumns.maximumValue == 8)
        #expect(gridColumns.step == 1)
        #expect(previewDelay.kind == .decimal)
        #expect(previewDelay.minimumValue == 0)
        #expect(previewDelay.maximumValue == 3)
        #expect(previewDelay.step == 0.05)
    }

    @Test func configurationFieldCodableRemainsCompatibleWithUnsectionedSchemas() throws {
        let field = LauncherConfigurationField(
            id: "count",
            variable: "count",
            title: "Count",
            kind: .integer,
            defaultValue: .integer(3)
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let roundTrip = try decoder.decode(
            LauncherConfigurationField.self,
            from: encoder.encode(field)
        )
        #expect(roundTrip == field)

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(field)) as? [String: Any]
        )
        legacyObject["section"] = nil
        legacyObject["minimumValue"] = nil
        legacyObject["maximumValue"] = nil
        legacyObject["step"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decodedLegacy = try decoder.decode(
            LauncherConfigurationField.self,
            from: legacyData
        )

        #expect(decodedLegacy.section == nil)
        #expect(decodedLegacy.minimumValue == nil)
        #expect(decodedLegacy.maximumValue == nil)
        #expect(decodedLegacy.step == nil)
    }

    @Test func launchAndBackgroundInvocationPresentResolvedConfiguration() async {
        let presenter = RecordingWindowSwitcherPresenter()
        let application = WindowSwitcherApplication(
            services: WindowSwitcherApplicationServices(presenter: presenter)
        )
        let settings = LauncherApplicationResolvedSettings(
            alias: "",
            hotKey: nil,
            isEnabled: true,
            configuration: [
                "layoutStyle": .text(WindowSwitcherLayoutStyle.list.rawValue),
                "replaceCommandTab": .boolean(true),
            ]
        )
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: settings
        )

        let launch = application.launch(in: context)
        guard case .dismiss = launch else {
            Issue.record("Expected the independent Window Switcher panel to dismiss the launcher")
            return
        }
        let result = await application.invokeInBackground(settings: settings)

        #expect(result == .success(message: "Window Switcher toggled."))
        #expect(presenter.presentedConfigurations.count == 2)
        #expect(presenter.presentedConfigurations.allSatisfy { $0.layoutStyle == .list })
        #expect(presenter.presentedConfigurations.allSatisfy { $0.replacesCommandTab })
        #expect(presenter.presentedConfigurations.allSatisfy { $0.shortcutMode == .toggleOverlay })
    }
}

@MainActor
private final class RecordingWindowSwitcherPresenter: WindowSwitcherPresenting {
    private(set) var presentedConfigurations: [WindowSwitcherConfiguration] = []

    func present(configuration: WindowSwitcherConfiguration) {
        presentedConfigurations.append(configuration)
    }
}
