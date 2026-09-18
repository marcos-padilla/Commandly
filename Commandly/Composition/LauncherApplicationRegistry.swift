import AIKit
import CommandKit
import Foundation
import Infrastructure
import SearchKit

/// A registered application that can be discovered and launched from Commandly.
///
/// Applications own their feature-specific model and surface construction. The launcher only
/// coordinates discovery, navigation, and the shared application-session contract.
@MainActor
protocol LauncherApplication {
    var definition: LauncherApplicationDefinition { get }
    /// Independently searchable entry points owned by this application.
    var toolDefinitions: [LauncherApplicationDefinition] { get }
    /// Typed launcher-query syntaxes that resolve to one of ``toolDefinitions``.
    var commandDefinitions: [LauncherApplicationCommandDefinition] { get }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch
    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch
}

extension LauncherApplication {
    var toolDefinitions: [LauncherApplicationDefinition] {
        guard definition.kind != .command,
              let manifest = definition.commandManifest else {
            return []
        }
        return [
            LauncherApplicationDefinition.tool(
                id: CommandID(rawValue: "\(definition.id.rawValue).tool.open"),
                parentID: definition.id,
                title: manifest.mode == .view ? "Open \(manifest.title)" : manifest.title,
                subtitle: manifest.subtitle,
                systemImage: manifest.systemImage,
                category: manifest.category,
                keywords: ["open", "launch"] + manifest.keywords
            )
        ]
    }

    var commandDefinitions: [LauncherApplicationCommandDefinition] { [] }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = toolID
        _ = arguments
        return launch(in: context)
    }
}

/// One parsed launcher phrase that invokes an application-owned tool with typed arguments.
struct LauncherApplicationCommandMatch: Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let reference: CommandReference
}

/// Declarative application-owned query parser. Commands are never shortcut targets themselves.
struct LauncherApplicationCommandDefinition: Identifiable, Sendable {
    let id: String
    let title: String
    let syntax: String
    let examples: [String]
    let toolID: CommandID
    private let parser: @Sendable (String) -> LauncherApplicationCommandMatch?

    init(
        id: String,
        title: String,
        syntax: String,
        examples: [String],
        toolID: CommandID,
        parser: @escaping @Sendable (String) -> LauncherApplicationCommandMatch?
    ) {
        self.id = id
        self.title = title
        self.syntax = syntax
        self.examples = examples
        self.toolID = toolID
        self.parser = parser
    }

    func match(_ query: String) -> LauncherApplicationCommandMatch? {
        parser(query)
    }
}

/// Opt-in behavior for applications whose assigned global shortcut must act without presenting
/// Commandly over the user's current app or recording.
@MainActor
protocol LauncherApplicationBackgroundInvoking {
    func invokeInBackground(
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult
}

/// Opt-in behavior for tools that can safely run without presenting the launcher.
@MainActor
protocol LauncherApplicationToolBackgroundInvoking {
    var backgroundToolIDs: Set<CommandID> { get }

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult
}

/// Launcher-shell navigation available while constructing an application session.
/// Feature services are injected into each application when it is registered.
@MainActor
struct LauncherApplicationContext {
    let navigation: LauncherApplicationNavigation
    let settings: LauncherApplicationResolvedSettings
}

/// File Search's focused dependency group.
@MainActor
struct FileSearchApplicationServices {
    let searchService: any FileSearching
    let urlOpener: any URLOpening
    let fileRevealer: any FileRevealing
    let fileActionService: any FileActionServicing
    let finderInfoPresenter: any FinderInfoPresenting
    let pasteboard: any PasteboardAccessing
}

/// Navigation callbacks shared by launcher applications.
@MainActor
struct LauncherApplicationNavigation {
    let dismissLauncher: () -> Void
    let openSettings: () -> Void
    let openAISettings: () -> Void
    let openPermissionsSettings: () -> Void
    let goBack: () -> Void

    init(
        dismissLauncher: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openAISettings: (() -> Void)? = nil,
        openPermissionsSettings: (() -> Void)? = nil,
        goBack: @escaping () -> Void
    ) {
        self.dismissLauncher = dismissLauncher
        self.openSettings = openSettings
        self.openAISettings = openAISettings ?? openSettings
        self.openPermissionsSettings = openPermissionsSettings ?? openSettings
        self.goBack = goBack
    }
}

/// Result of launching a registered application.
@MainActor
enum LauncherApplicationLaunch {
    case present(LauncherApplicationSession)
    case openSettings
    case dismiss
    case message(String)
}

enum LauncherApplicationRegistryError: Error, Equatable {
    case duplicateApplication(CommandID)
    case missingParent(child: CommandID, parent: CommandID)
    case invalidParent(CommandID)
    case invalidDefinition(CommandID, reason: String)
}

/// The single source of truth for applications exposed by the launcher.
@MainActor
final class LauncherApplicationRegistry {
    private let preferencesStore: any LauncherApplicationPreferencesStoring
    private var definitions: [CommandID: LauncherApplicationDefinition] = [:]
    private var applications: [CommandID: any LauncherApplication] = [:]
    private var applicationIDByToolID: [CommandID: CommandID] = [:]
    private var commandDefinitionsByApplicationID:
        [CommandID: [LauncherApplicationCommandDefinition]] = [:]
    private var rootIDs: Set<CommandID> = []
    private var childIDsByParent: [CommandID: Set<CommandID>] = [:]

    init(
        preferencesStore: any LauncherApplicationPreferencesStoring =
            InMemoryLauncherApplicationPreferencesStore()
    ) {
        self.preferencesStore = preferencesStore
    }

    func register(_ definition: LauncherApplicationDefinition) throws {
        try validate(definition)
        guard definitions[definition.id] == nil else {
            throw LauncherApplicationRegistryError.duplicateApplication(definition.id)
        }
        definitions[definition.id] = definition
        if let parentID = definition.parentID {
            childIDsByParent[parentID, default: []].insert(definition.id)
        } else {
            rootIDs.insert(definition.id)
        }
    }

    func register(_ application: any LauncherApplication) throws {
        let definition = application.definition
        guard definition.commandManifest != nil else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Launchable applications require a command manifest."
            )
        }
        guard let documentation = definition.documentation else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Launchable applications require documentation."
            )
        }
        try validate(documentation, for: definition.id)
        try register(definition)
        guard applications[definition.id] == nil else {
            removeDefinition(definition)
            let id = definition.id
            throw LauncherApplicationRegistryError.duplicateApplication(id)
        }
        applications[definition.id] = application
        do {
            try registerToolsAndCommands(for: application)
        } catch {
            applications[definition.id] = nil
            for toolID in applicationIDByToolID.compactMap({
                $0.value == definition.id ? $0.key : nil
            }) {
                if let toolDefinition = definitions[toolID] {
                    removeDefinition(toolDefinition)
                }
                applicationIDByToolID[toolID] = nil
            }
            commandDefinitionsByApplicationID[definition.id] = nil
            removeDefinition(definition)
            throw error
        }
    }

    /// Atomically refreshes an application's dynamic tools while preserving their saved preferences.
    /// A failed validation restores the complete prior catalog; other applications are untouched.
    func refreshTools(for applicationID: CommandID) throws {
        guard let application = applications[applicationID] else {
            throw LauncherApplicationRegistryError.invalidDefinition(applicationID, reason: "Application is not registered.")
        }
        let oldDefinitions = definitions
        let oldOwners = applicationIDByToolID
        let oldCommands = commandDefinitionsByApplicationID
        let oldRoots = rootIDs
        let oldChildren = childIDsByParent
        for toolID in applicationIDByToolID.compactMap({ $0.value == applicationID ? $0.key : nil }) {
            if let definition = definitions[toolID] { removeDefinition(definition) }
            applicationIDByToolID[toolID] = nil
        }
        commandDefinitionsByApplicationID[applicationID] = nil
        do { try registerToolsAndCommands(for: application) }
        catch {
            definitions = oldDefinitions; applicationIDByToolID = oldOwners
            commandDefinitionsByApplicationID = oldCommands; rootIDs = oldRoots; childIDsByParent = oldChildren
            throw error
        }
    }

    func application(for id: CommandID) -> (any LauncherApplication)? {
        applications[id]
    }

    func enabledApplication(for id: CommandID) -> (any LauncherApplication)? {
        guard isEffectivelyEnabled(id) else { return nil }
        return applications[id]
    }

    func owningApplicationID(for commandID: CommandID) -> CommandID? {
        if applications[commandID] != nil {
            return commandID
        }
        return applicationIDByToolID[commandID]
    }

    func owningApplication(for commandID: CommandID) -> (any LauncherApplication)? {
        owningApplicationID(for: commandID).flatMap { applications[$0] }
    }

    func isLaunchableCommand(_ id: CommandID) -> Bool {
        owningApplicationID(for: id) != nil
    }

    func isBackgroundInvokingCommand(_ id: CommandID) -> Bool {
        guard let application = owningApplication(for: id) else { return false }
        if applications[id] != nil {
            return application is any LauncherApplicationBackgroundInvoking
        }
        guard let toolApplication = application
                as? any LauncherApplicationToolBackgroundInvoking else {
            return false
        }
        return toolApplication.backgroundToolIDs.contains(id)
    }

    func commands(for applicationID: CommandID) -> [LauncherApplicationCommandDefinition] {
        commandDefinitionsByApplicationID[applicationID] ?? []
    }

    func commandMatches(_ query: String) -> [LauncherApplicationCommandMatch] {
        commandDefinitionsByApplicationID
            .keys
            .sorted { $0.rawValue < $1.rawValue }
            .filter { isEffectivelyEnabled($0) }
            .flatMap { applicationID in
                (commandDefinitionsByApplicationID[applicationID] ?? []).compactMap {
                    guard isEffectivelyEnabled($0.toolID) else { return nil }
                    return $0.match(query)
                }
            }
    }

    func definition(for id: CommandID) -> LauncherApplicationDefinition? {
        definitions[id]
    }

    func allDefinitions() -> [LauncherApplicationDefinition] {
        definitions.values.sorted(by: Self.sortDefinitions)
    }

    func rootDefinitions() -> [LauncherApplicationDefinition] {
        rootIDs
            .compactMap { definitions[$0] }
            .sorted(by: Self.sortDefinitions)
    }

    func children(of id: CommandID) -> [LauncherApplicationDefinition] {
        (childIDsByParent[id] ?? [])
            .compactMap { definitions[$0] }
            .sorted(by: Self.sortDefinitions)
    }

    func resolvedSettings(for id: CommandID) -> LauncherApplicationResolvedSettings? {
        guard let definition = definitions[id] else { return nil }
        let preferences = preferencesStore.preferences(for: id)
        var configuration = Dictionary(
            uniqueKeysWithValues: definition.configurationFields.map {
                ($0.variable, $0.defaultValue)
            }
        )
        for field in definition.configurationFields {
            guard let value = preferences.configuration[field.variable],
                  field.kind.accepts(value) else {
                continue
            }
            if field.kind == .selection,
               let selection = value.textValue,
               field.options.contains(where: { $0.id == selection }) == false {
                continue
            }
            configuration[field.variable] = value
        }
        let tags = Self.normalizedTags(
            definition.defaultTags
                + (preferences.tags ?? [])
                + [preferences.alias ?? ""]
        )
        return LauncherApplicationResolvedSettings(
            alias: Self.normalizedAlias(preferences.alias ?? ""),
            tags: tags,
            hotKey: preferences.hasHotKeyOverride ? preferences.hotKey : definition.defaultHotKey,
            isEnabled: preferences.isEnabled ?? definition.isEnabledByDefault,
            configuration: configuration
        )
    }

    func isEffectivelyEnabled(_ id: CommandID) -> Bool {
        var currentID: CommandID? = id
        var visited: Set<CommandID> = []
        while let candidate = currentID {
            guard visited.insert(candidate).inserted,
                  let definition = definitions[candidate],
                  isIndividuallyEnabled(definition) else {
                return false
            }
            currentID = definition.parentID
        }
        return true
    }

    func allManifests() -> [CommandManifest] {
        allKnownManifests()
            .filter { isEffectivelyEnabled($0.id) }
    }

    /// Metadata for every registered launchable application, including disabled applications.
    ///
    /// Search continues to use ``allManifests()`` so disabled applications stay undiscoverable;
    /// persisted references use this complete catalog so they can render as unavailable instead
    /// of appearing to have been removed.
    func allKnownManifests() -> [CommandManifest] {
        definitions.values
            .filter { isLaunchableCommand($0.id) }
            .compactMap { taggedManifest(for: $0) }
            .sorted {
                let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return $0.id.rawValue < $1.id.rawValue
            }
    }

    private func taggedManifest(
        for definition: LauncherApplicationDefinition
    ) -> CommandManifest? {
        guard let manifest = definition.commandManifest else { return nil }
        let tags = resolvedSettings(for: definition.id)?.tags ?? definition.defaultTags
        return CommandManifest(
            id: manifest.id,
            title: manifest.title,
            subtitle: manifest.subtitle,
            systemImage: manifest.systemImage,
            category: manifest.category,
            mode: manifest.mode,
            keywords: Self.normalizedTags(tags + manifest.keywords),
            arguments: manifest.arguments,
            availabilityRequirements: manifest.availabilityRequirements,
            badgeTitle: manifest.badgeTitle,
            defaultActions: manifest.defaultActions
        )
    }

    func savePreferences(_ preferences: LauncherApplicationPreferences, for id: CommandID) {
        guard definitions[id] != nil else { return }
        preferencesStore.save(preferences, for: id)
    }

    func preferences(for id: CommandID) -> LauncherApplicationPreferences {
        preferencesStore.preferences(for: id)
    }

    func resetPreferences(for id: CommandID) {
        preferencesStore.resetPreferences(for: id)
    }

    static func makeBuiltIn(
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        fileSearchServices: FileSearchApplicationServices = .inMemory,
        fileBrowserFolderAccessStore: any FolderAccessStoring = InMemoryFolderAccessStore(),
        fileBrowserServiceOverride: (any FileBrowsing)? = nil,
        calculatorSessionStore: CalculatorSessionStore = CalculatorSessionStore(),
        downloadsServices: DownloadsApplicationServices? = nil,
        logosServices: LogosApplicationServices? = nil,
        backgroundRemovalService: any BackgroundRemoving = NativeBackgroundRemovalService(),
        imageConversionService: any ImageConverting = NativeImageConversionService(),
        imageRecognitionService: any ImageRecognizing = NativeImageRecognitionService(),
        timerStore: TimerStore = TimerStore(),
        financeServices: FinanceApplicationServices = .inMemory,
        markdownPreviewServices: MarkdownPreviewApplicationServices = .inMemory,
        productivityLibraryServices: ProductivityLibraryApplicationServices = .inMemory,
        scheduleServices: ScheduleApplicationServices = .inMemory,
        cameraServices: CameraApplicationServices = .inMemory,
        screenshotServices: ScreenshotApplicationServices = .inMemory,
        screenRecordingPresenter: (any ScreenRecordingPresenting)? = nil,
        displayResolutionServices: DisplayResolutionApplicationServices = .inMemory(),
        systemSettingsServices: SystemSettingsApplicationServices = .inMemory,
        menuBarShortcutController: MenuBarShortcutController? = nil,
        offlineToolsServices: OfflineToolsServices? = nil,
        finderAIServices: FinderAIApplicationServices = .inMemory,
        quickAIServices: QuickAIApplicationServices = .inMemory,
        aiAgentsServices: AIAgentsApplicationServices = .inMemory,
        visualAIServices: VisualAIApplicationServices = .inMemory,
        externalAgentServices: ExternalAgentApplicationServices = .unavailable,
        emojiServices: EmojiSearchApplicationServices? = nil,
        dictationServices: DictationApplicationServices? = nil,
        gifSearchServices: GIFSearchApplicationServices = .unavailable,
        slackEmojiServices: SlackEmojiApplicationServices = .unavailable,
        notionWorkspaceServices: NotionWorkspaceApplicationServices = .unavailable,
        finderPathServices: FinderPathApplicationServices = .unavailable,
        appMenusServices: AppMenusApplicationServices = .unavailable,
        writingToolsServices: WritingToolsApplicationServices = .inMemory,
        translationServices: TranslationApplicationServices = .inMemory,
        windowLayoutsServices: WindowLayoutsApplicationServices = WindowLayoutsApplicationServices(
            layoutService: InMemoryWindowLayoutService(),
            customStore: InMemoryCustomWindowLayoutStore()
        ),
        systemActivityService: any SystemActivityServicing = NativeSystemActivityService(),
        portManagerService: any PortManaging = NativePortManager(),
        storageCleanupScanner: any StorageCleanupScanning = InMemoryStorageCleanupScanner(),
        storageCleanupDirectoryChooser: any StorageCleanupDirectoryChoosing =
            InMemoryStorageCleanupDirectoryChooser(),
        storageCleanupTrashManager: any ApplicationBundleManaging =
            InMemoryApplicationBundleManager(),
        microphoneControlService: any MicrophoneControlling = NativeMicrophoneControlService(),
        highlightModeService: any HighlightModeControlling = InMemoryHighlightModeService(),
        windowSwitcherServices: WindowSwitcherApplicationServices = .inMemory,
        includesWindowSwitcher: Bool = true,
        preferencesStore: any LauncherApplicationPreferencesStoring =
            InMemoryLauncherApplicationPreferencesStore(),
        shelfLaunchController: ShelfLaunchController = ShelfLaunchController()
    ) -> LauncherApplicationRegistry {
        let registry = LauncherApplicationRegistry(preferencesStore: preferencesStore)
        let resolvedOfflineToolsServices = offlineToolsServices ?? OfflineToolsServices(
            pasteboard: fileSearchServices.pasteboard
        )
        let resolvedDownloadsServices = downloadsServices ?? DownloadsApplicationServices(
            provider: NativeRecentDownloadsService(),
            urlOpener: fileSearchServices.urlOpener,
            fileRevealer: fileSearchServices.fileRevealer,
            pasteboard: fileSearchServices.pasteboard
        )
        let resolvedLogosServices = logosServices ?? .live(
            pasteboard: fileSearchServices.pasteboard
        )
        do {
            try registry.register(BuiltInLauncherApplicationGroup.catalog)
            try registry.register(BuiltInLauncherApplicationGroup.aiExtensions)
            try registry.register(OpenSettingsApplication())
            try registry.register(
                ClipboardHistoryApplication(store: clipboardHistoryStore)
            )
            try registry.register(
                FileSearchApplication(services: fileSearchServices)
            )
            try registry.register(FileBrowserApplication(
                folderAccessStore: fileBrowserFolderAccessStore,
                urlOpener: fileSearchServices.urlOpener,
                browser: fileBrowserServiceOverride
            ))
            try registry.register(
                CalculatorHistoryApplication(
                    sessionStore: calculatorSessionStore,
                    pasteboard: fileSearchServices.pasteboard
                )
            )
            try registry.register(DownloadsApplication(services: resolvedDownloadsServices))
            try registry.register(LogosApplication(services: resolvedLogosServices))
            try registry.register(
                BackgroundRemoverApplication(remover: backgroundRemovalService)
            )
            try registry.register(ImageToolsApplication(
                converter: imageConversionService,
                recognizer: imageRecognitionService,
                pasteboard: fileSearchServices.pasteboard,
                urlOpener: fileSearchServices.urlOpener
            ))
            try registry.register(ScheduleApplication(services: scheduleServices))
            try registry.register(CameraApplication(services: cameraServices))
            try registry.register(ScreenshotApplication(services: screenshotServices))
            try registry.register(ScreenRecordingApplication(presenter: screenRecordingPresenter))
            try registry.register(DisplayResolutionApplication(services: displayResolutionServices))
            try registry.register(MenuBarShortcutsApplication(controller: menuBarShortcutController))
            try registry.register(CelebrationApplication())
            try registry.register(TimersApplication(store: timerStore))
            try registry.register(FinanceApplication(services: financeServices))
            try registry.register(
                MarkdownPreviewApplication(
                    services: markdownPreviewServices,
                    urlOpener: fileSearchServices.urlOpener
                )
            )
            try registry.register(ShelfApplication(launchController: shelfLaunchController))
            try registry.register(
                ProductivityLibraryApplication(services: productivityLibraryServices)
            )
            try registry.register(SystemSettingsCatalogApplication(services: systemSettingsServices))
            try registry.register(SystemActivityApplication(service: systemActivityService))
            try registry.register(PortManagerApplication(service: portManagerService))
            try registry.register(
                StorageCleanerApplication(
                    scanner: storageCleanupScanner,
                    directoryChooser: storageCleanupDirectoryChooser,
                    trashManager: storageCleanupTrashManager
                )
            )
            try registry.register(MicrophoneControlApplication(service: microphoneControlService))
            try registry.register(HighlightModeApplication(service: highlightModeService))
            if includesWindowSwitcher {
                try registry.register(WindowSwitcherApplication(services: windowSwitcherServices))
            }
            try registry.register(WindowLayoutsApplication(services: windowLayoutsServices))
            try registry.register(FinderAIApplication(services: finderAIServices))
            try registry.register(QuickAIApplication(services: quickAIServices))
            try registry.register(AIAgentsApplication(services: aiAgentsServices))
            try registry.register(VisualAIApplication(services: visualAIServices))
            try registry.register(ExternalAgentApplication(kind: .hermes, services: externalAgentServices))
            try registry.register(ExternalAgentApplication(kind: .openClaw, services: externalAgentServices))
            try registry.register(WritingToolsApplication(services: writingToolsServices))
            try registry.register(TranslationApplication(services: translationServices))
            try registry.register(EmojiSearchApplication(services: emojiServices ?? .live(
                pasteboard: resolvedOfflineToolsServices.pasteboard,
                quickAI: quickAIServices.chat
            )))
            try registry.register(DictationApplication(services: dictationServices ?? .live(
                pasteboard: resolvedOfflineToolsServices.pasteboard, quickAI: quickAIServices.chat
            )))
            try registry.register(GIFSearchApplication(services: gifSearchServices))
            try registry.register(SlackEmojiApplication(services: slackEmojiServices))
            try registry.register(NotionWorkspaceApplication(services: notionWorkspaceServices))
            try registry.register(FinderPathApplication(services: finderPathServices))
            try registry.register(AppMenusApplication(services: appMenusServices))
            for tool in OfflineToolKind.allCases where tool != .emoji {
                try registry.register(
                    OfflineToolsApplication(tool: tool, services: resolvedOfflineToolsServices)
                )
            }
        } catch {
            preconditionFailure("Built-in launcher application definitions must be valid: \(error)")
        }
        return registry
    }

    private func registerToolsAndCommands(
        for application: any LauncherApplication
    ) throws {
        let applicationID = application.definition.id
        let tools = application.toolDefinitions
        guard Set(tools.map(\.id)).count == tools.count else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                applicationID,
                reason: "Application tool identifiers must be unique."
            )
        }
        for tool in tools {
            guard tool.kind == .tool,
                  tool.parentID == applicationID,
                  tool.commandManifest != nil else {
                throw LauncherApplicationRegistryError.invalidDefinition(
                    applicationID,
                    reason: "Tools require a tool definition, owning parent, and command manifest."
                )
            }
            try register(tool)
            applicationIDByToolID[tool.id] = applicationID
        }

        let commands = application.commandDefinitions
        guard Set(commands.map(\.id)).count == commands.count,
              commands.allSatisfy({ command in
                  applicationIDByToolID[command.toolID] == applicationID
              }) else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                applicationID,
                reason: "Commands must have unique IDs and target a tool owned by the application."
            )
        }
        commandDefinitionsByApplicationID[applicationID] = commands
    }

    private func validate(_ definition: LauncherApplicationDefinition) throws {
        if definition.kind == .group, definition.commandManifest != nil {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Groups cannot declare launch manifests."
            )
        }
        if let manifest = definition.commandManifest, manifest.id != definition.id {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Definition and command manifest identifiers must match."
            )
        }
        if definition.kind == .tool, definition.parentID == nil {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Tools require an owning application."
            )
        }
        if let parentID = definition.parentID {
            guard parentID != definition.id else {
                throw LauncherApplicationRegistryError.invalidParent(definition.id)
            }
            guard definitions[parentID] != nil else {
                throw LauncherApplicationRegistryError.missingParent(
                    child: definition.id,
                    parent: parentID
                )
            }
        }
        guard Set(definition.configurationFields.map(\.id)).count
                == definition.configurationFields.count,
              Set(definition.configurationFields.map(\.variable)).count
                == definition.configurationFields.count else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Configuration field identifiers and variables must be unique."
            )
        }
        for field in definition.configurationFields {
            guard field.variable.isEmpty == false,
                  field.kind.accepts(field.defaultValue) else {
                throw LauncherApplicationRegistryError.invalidDefinition(
                    definition.id,
                    reason: "Configuration defaults must match their field type."
                )
            }
            if field.kind == .selection {
                guard let defaultID = field.defaultValue.textValue,
                      Set(field.options.map(\.id)).count == field.options.count,
                      field.options.contains(where: { $0.id == defaultID }) else {
                    throw LauncherApplicationRegistryError.invalidDefinition(
                        definition.id,
                        reason: "Selection defaults must reference a declared option."
                    )
                }
            }
        }
    }

    private func validate(
        _ documentation: LauncherApplicationDocumentation,
        for id: CommandID
    ) throws {
        guard documentation.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                == false,
              documentation.sections.isEmpty == false else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                id,
                reason: "Documentation requires an overview and at least one section."
            )
        }
        let sectionIDs = documentation.sections.map(\.id)
        guard Set(sectionIDs).count == sectionIDs.count,
              documentation.sections.allSatisfy({
                  $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && $0.blocks.isEmpty == false
              }) else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                id,
                reason: "Documentation section identifiers must be unique and sections nonempty."
            )
        }
        let blocks = documentation.sections.flatMap(\.blocks)
        let blockIDs = blocks.map(\.id)
        guard Set(blockIDs).count == blockIDs.count,
              blocks.allSatisfy({
                  $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && isValidDocumentationBlock($0)
              })
        else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                id,
                reason: "Documentation blocks must have unique IDs and nonempty content."
            )
        }
    }

    private func isValidDocumentationBlock(_ block: DocumentationBlock) -> Bool {
        switch block.content {
        case .paragraph(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .bullets(let items), .steps(let items):
            return items.isEmpty == false && items.allSatisfy(Self.isNonempty)
        case .shortcuts(let shortcuts):
            return shortcuts.isEmpty == false
                && Set(shortcuts.map(\.id)).count == shortcuts.count
                && shortcuts.allSatisfy { shortcut in
                    Self.isNonempty(shortcut.id)
                        && Self.isNonempty(shortcut.title)
                        && shortcut.keys.isEmpty == false
                        && shortcut.keys.allSatisfy(Self.isNonempty)
                }
        case .examples(let examples):
            return examples.isEmpty == false
                && Set(examples.map(\.id)).count == examples.count
                && examples.allSatisfy { example in
                    Self.isNonempty(example.id) && Self.isNonempty(example.input)
                }
        case .callout(let callout):
            return Self.isNonempty(callout.title) && Self.isNonempty(callout.text)
        }
    }

    private static func isNonempty(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func isIndividuallyEnabled(_ definition: LauncherApplicationDefinition) -> Bool {
        preferencesStore.preferences(for: definition.id).isEnabled
            ?? definition.isEnabledByDefault
    }

    private func removeDefinition(_ definition: LauncherApplicationDefinition) {
        definitions[definition.id] = nil
        if let parentID = definition.parentID {
            childIDsByParent[parentID]?.remove(definition.id)
        } else {
            rootIDs.remove(definition.id)
        }
    }

    private static func normalizedAlias(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false else { return nil }
            let key = normalized.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func sortDefinitions(
        _ left: LauncherApplicationDefinition,
        _ right: LauncherApplicationDefinition
    ) -> Bool {
        if left.order != right.order { return left.order < right.order }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}

enum BuiltInLauncherApplicationGroup {
    static let catalogID = CommandID(rawValue: "commandly.catalog")
    static let aiExtensionsID = CommandID(rawValue: "commandly.ai-extensions")

    static let catalog = LauncherApplicationDefinition.group(
        id: catalogID,
        title: "Commandly Applications",
        subtitle: "Built-in launcher applications and commands",
        systemImage: "square.grid.2x2",
        order: 0
    )

    static let aiExtensions = LauncherApplicationDefinition.group(
        id: aiExtensionsID,
        title: "AI Extensions",
        subtitle: "Tools powered by your active AI provider",
        systemImage: "sparkles.rectangle.stack",
        order: 10
    )
}

extension FileSearchApplicationServices {
    static var inMemory: FileSearchApplicationServices {
        FileSearchApplicationServices(
            searchService: InMemoryFileSearchService(),
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            fileActionService: InMemoryFileActionService(),
            finderInfoPresenter: InMemoryFinderInfoPresenter(),
            pasteboard: SystemPasteboard()
        )
    }
}
