import CommandKit
import Infrastructure
import MarkdownPreviewKit
import SwiftUI

/// Reads Markdown locally in Commandly and shares its rendering preferences with Quick Look.
@MainActor
struct MarkdownPreviewApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "documents.markdown-preview")
    static let openToolID = CommandID(rawValue: "documents.markdown-preview.open")
    static let chooseDocumentToolID = CommandID(
        rawValue: "documents.markdown-preview.choose-document"
    )

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Markdown Preview",
        subtitle: "Read Markdown in Commandly and Finder",
        systemImage: "doc.richtext",
        category: .productivity,
        mode: .view,
        keywords: [
            "Markdown", "preview", "Quick Look", "Finder", "GFM", "read", "viewer",
            "HTML", "PDF", "Mermaid", "math", "diagram", "front matter", "MDX", "Quarto"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.chooseDocument,
                title: "Choose Markdown File",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    static let configurationFields: [LauncherConfigurationField] = [
        LauncherConfigurationField(
            id: "preview-theme",
            variable: Setting.previewTheme,
            title: "Preview appearance",
            description: "Choose whether Markdown follows macOS or uses a fixed appearance.",
            section: "Appearance",
            kind: .selection,
            defaultValue: .text(MarkdownTheme.system.rawValue),
            options: [
                LauncherConfigurationOption(id: MarkdownTheme.system.rawValue, title: "System"),
                LauncherConfigurationOption(id: MarkdownTheme.light.rawValue, title: "Light"),
                LauncherConfigurationOption(id: MarkdownTheme.dark.rawValue, title: "Dark")
            ]
        ),
        LauncherConfigurationField(
            id: "enable-mermaid",
            variable: Setting.enableMermaid,
            title: "Mermaid diagrams",
            description: "Render the supported safe Mermaid subset and preserve source otherwise.",
            section: "Rendering",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "enable-math",
            variable: Setting.enableMath,
            title: "Math notation",
            description: "Give inline and block math a local typographic treatment.",
            section: "Rendering",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "enable-emoji",
            variable: Setting.enableEmoji,
            title: "Emoji shortcodes",
            description: "Render supported GitHub-style codes such as :smile:.",
            section: "Rendering",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "enable-typst",
            variable: Setting.enableTypst,
            title: "Typst math",
            description: "Preview supported Typst-shaped math while retaining its source.",
            section: "Rendering",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "collapse-blockquotes",
            variable: Setting.collapseBlockquotes,
            title: "Collapse blockquotes",
            description: "Start ordinary quotes and alert blocks collapsed.",
            section: "Rendering",
            kind: .toggle,
            defaultValue: .boolean(false)
        ),
        LauncherConfigurationField(
            id: "show-line-numbers",
            variable: Setting.showLineNumbers,
            title: "Show line numbers",
            description: "Display source and fenced-code line gutters.",
            section: "Rendering",
            kind: .toggle,
            defaultValue: .boolean(false)
        ),
        LauncherConfigurationField(
            id: "base-font-size",
            variable: Setting.baseFontSize,
            title: "Base font size",
            description: "Set the reading size used in Commandly.",
            section: "Typography",
            kind: .integer,
            defaultValue: .integer(14),
            minimumValue: 12,
            maximumValue: 24,
            step: 1
        ),
        LauncherConfigurationField(
            id: "finder-font-size",
            variable: Setting.finderFontSize,
            title: "Finder preview font size",
            description: "Set the compact reading size used by Finder Quick Look.",
            section: "Typography",
            kind: .integer,
            defaultValue: .integer(13),
            minimumValue: 10,
            maximumValue: 24,
            step: 1
        ),
        LauncherConfigurationField(
            id: "code-theme",
            variable: Setting.codeTheme,
            title: "Code highlighting theme",
            description: "Choose the local color treatment used for fenced code.",
            section: "Typography",
            kind: .selection,
            defaultValue: .text(MarkdownCodeTheme.adaptive.rawValue),
            options: [
                LauncherConfigurationOption(id: MarkdownCodeTheme.adaptive.rawValue, title: "Default"),
                LauncherConfigurationOption(id: MarkdownCodeTheme.github.rawValue, title: "GitHub"),
                LauncherConfigurationOption(id: MarkdownCodeTheme.monokai.rawValue, title: "Monokai"),
                LauncherConfigurationOption(
                    id: MarkdownCodeTheme.atomOneDark.rawValue,
                    title: "Atom One Dark"
                )
            ]
        ),
        LauncherConfigurationField(
            id: "show-outline",
            variable: Setting.showOutline,
            title: "Show outline",
            description: "Open the heading outline when a document loads.",
            section: "Reading",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "automatic-reload",
            variable: Setting.automaticReload,
            title: "Automatic reload",
            description: "Follow external saves while this document is open.",
            section: "Reading",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "remember-scroll",
            variable: Setting.rememberScroll,
            title: "Remember scroll position",
            description: "Restore bounded reading state using a digest instead of a stored path.",
            section: "Reading",
            kind: .toggle,
            defaultValue: .boolean(true)
        ),
        LauncherConfigurationField(
            id: "default-view",
            variable: Setting.defaultView,
            title: "Default view",
            description: "Open documents as rendered Markdown or escaped source.",
            section: "Reading",
            kind: .selection,
            defaultValue: .text(SourceViewMode.rendered.rawValue),
            options: [
                LauncherConfigurationOption(id: SourceViewMode.rendered.rawValue, title: "Preview"),
                LauncherConfigurationOption(id: SourceViewMode.source.rawValue, title: "Source")
            ]
        ),
        LauncherConfigurationField(
            id: "default-zoom",
            variable: Setting.defaultZoom,
            title: "Default zoom",
            description: "Set the initial reflow zoom from 0.5× through 3×.",
            section: "Reading",
            kind: .decimal,
            defaultValue: .decimal(1),
            minimumValue: 0.5,
            maximumValue: 3,
            step: 0.05
        )
    ]

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 36,
        configurationFields: Self.configurationFields,
        documentation: RegisteredApplicationDocumentation.markdownPreview
    )

    private let services: MarkdownPreviewApplicationServices
    private let urlOpener: any URLOpening

    init(
        services: MarkdownPreviewApplicationServices,
        urlOpener: any URLOpening = NoOpURLOpener()
    ) {
        self.services = services
        self.urlOpener = urlOpener
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: Self.openToolID,
                parentID: Self.applicationID,
                title: "Open Markdown Preview",
                subtitle: "Open the local Markdown reader",
                systemImage: "doc.richtext",
                category: .productivity,
                keywords: ["open", "reader", "viewer", "Markdown", "preview"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.chooseDocumentToolID,
                parentID: Self.applicationID,
                title: "Choose Markdown File",
                subtitle: "Open the file picker and select a Markdown document",
                systemImage: "doc.badge.plus",
                category: .productivity,
                order: 1,
                keywords: [
                    "choose", "open file", "pick file", "Markdown", "MDX", "Quarto", "reader"
                ]
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(choosesDocument: false, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case Self.openToolID:
            return makeLaunch(choosesDocument: false, context: context)
        case Self.chooseDocumentToolID:
            return makeLaunch(choosesDocument: true, context: context)
        default:
            return .message("Markdown Preview tool is unavailable.")
        }
    }

    private func makeLaunch(
        choosesDocument: Bool,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let configuration = Self.configuration(from: context.settings)
        let webController = MarkdownPreviewWebController(urlOpener: urlOpener)
        let model = MarkdownPreviewViewModel(
            loader: services.loader,
            renderer: services.renderer,
            watcher: services.watcher,
            scrollStore: services.scrollStore,
            configuration: configuration,
            webController: webController,
            autoReload: configuration.automaticallyReloads,
            onGoBack: context.navigation.goBack
        )
        webController.onOpenMarkdownDocument = { [weak model] url in
            model?.open(url)
        }
        if choosesDocument {
            model.chooseDocument()
        }
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                MarkdownPreviewView(viewModel: $0, webController: webController)
            }
        )
    }

    static func configuration(
        from settings: LauncherApplicationResolvedSettings
    ) -> MarkdownPreviewConfiguration {
        let defaults = MarkdownPreviewConfiguration.default
        let theme = text(Setting.previewTheme, in: settings)
            .flatMap(MarkdownTheme.init(rawValue:)) ?? defaults.theme
        let codeTheme = text(Setting.codeTheme, in: settings)
            .flatMap(MarkdownCodeTheme.init(rawValue:)) ?? defaults.codeTheme
        let sourceMode = text(Setting.defaultView, in: settings)
            .flatMap(SourceViewMode.init(rawValue:)) ?? defaults.sourceViewMode
        let enablesMath = boolean(Setting.enableMath, in: settings) ?? defaults.enablesMath

        return MarkdownPreviewConfiguration(
            theme: theme,
            codeTheme: codeTheme,
            fontFamily: .system,
            sourceViewMode: sourceMode,
            linkPolicy: .webEmailAndRelativeMarkdown,
            imagePolicy: .embeddedDataOnly,
            diagramMode: .safePreview,
            mathMode: enablesMath ? .styledText : .disabled,
            fontSize: Double(integer(Setting.baseFontSize, in: settings) ?? Int(defaults.fontSize)),
            finderFontSize: Double(
                integer(Setting.finderFontSize, in: settings) ?? Int(defaults.finderFontSize)
            ),
            lineHeight: defaults.lineHeight,
            contentWidth: defaults.contentWidth,
            initialZoom: decimal(Setting.defaultZoom, in: settings) ?? defaults.initialZoom,
            tabWidth: defaults.tabWidth,
            showsTableOfContents: boolean(Setting.showOutline, in: settings)
                ?? defaults.showsTableOfContents,
            rendersFrontMatter: defaults.rendersFrontMatter,
            enablesTables: defaults.enablesTables,
            enablesTaskLists: defaults.enablesTaskLists,
            enablesStrikethrough: defaults.enablesStrikethrough,
            enablesAlerts: defaults.enablesAlerts,
            enablesEmoji: boolean(Setting.enableEmoji, in: settings) ?? defaults.enablesEmoji,
            enablesMath: enablesMath,
            enablesTypst: boolean(Setting.enableTypst, in: settings) ?? defaults.enablesTypst,
            enablesMermaid: boolean(Setting.enableMermaid, in: settings)
                ?? defaults.enablesMermaid,
            enablesGraphviz: defaults.enablesGraphviz,
            enablesVega: defaults.enablesVega,
            showsLineNumbers: boolean(Setting.showLineNumbers, in: settings)
                ?? defaults.showsLineNumbers,
            softBreaksAsLineBreaks: defaults.softBreaksAsLineBreaks,
            collapsesBlockquotes: boolean(Setting.collapseBlockquotes, in: settings)
                ?? defaults.collapsesBlockquotes,
            automaticallyReloads: boolean(Setting.automaticReload, in: settings)
                ?? defaults.automaticallyReloads,
            remembersScrollPosition: boolean(Setting.rememberScroll, in: settings)
                ?? defaults.remembersScrollPosition
        )
    }

    enum Setting {
        static let previewTheme = "previewTheme"
        static let enableMermaid = "enableMermaid"
        static let enableMath = "enableMath"
        static let enableEmoji = "enableEmoji"
        static let enableTypst = "enableTypst"
        static let collapseBlockquotes = "collapseBlockquotes"
        static let showLineNumbers = "showLineNumbers"
        static let baseFontSize = "baseFontSize"
        static let finderFontSize = "finderFontSize"
        static let codeTheme = "codeTheme"
        static let showOutline = "showOutline"
        static let automaticReload = "automaticReload"
        static let rememberScroll = "rememberScroll"
        static let defaultView = "defaultView"
        static let defaultZoom = "defaultZoom"
    }

    private static func text(
        _ variable: String,
        in settings: LauncherApplicationResolvedSettings
    ) -> String? {
        settings.value(for: variable)?.textValue
    }

    private static func boolean(
        _ variable: String,
        in settings: LauncherApplicationResolvedSettings
    ) -> Bool? {
        settings.value(for: variable)?.booleanValue
    }

    private static func integer(
        _ variable: String,
        in settings: LauncherApplicationResolvedSettings
    ) -> Int? {
        settings.value(for: variable)?.integerValue
    }

    private static func decimal(
        _ variable: String,
        in settings: LauncherApplicationResolvedSettings
    ) -> Double? {
        settings.value(for: variable)?.decimalValue
    }
}
