import CommandKit
import SwiftUI

enum ProductivityLibraryApplicationID {
    static let openTool = CommandID(rawValue: "productivity.library.open")
    static let newSnippetTool = CommandID(rawValue: "productivity.library.new-snippet")
    static let newQuickNoteTool = CommandID(rawValue: "productivity.library.new-quick-note")
    static let newFloatingNoteTool = CommandID(rawValue: "productivity.library.new-floating-note")
    static let newQuicklinkTool = CommandID(rawValue: "productivity.library.new-quicklink")
    static let newEmojiKeywordTool = CommandID(
        rawValue: "productivity.library.new-emoji-keyword"
    )
}

/// Registered local-first library for snippets, notes, Quicklinks, and emoji keywords.
@MainActor
struct ProductivityLibraryApplication: LauncherApplication {
    static let id = CommandID(rawValue: "productivity.library")

    private static let manifest = CommandManifest(
        id: id,
        title: "Productivity Library",
        subtitle: "Snippets, quick notes, Quicklinks, and emoji keywords",
        systemImage: "books.vertical",
        category: .productivity,
        mode: .view,
        keywords: [
            "snippet", "note", "quicklink", "bookmark", "emoji", "text", "clipboard"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: ProductivityLibraryActionID.useSelected,
                title: "Use Item",
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

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 40,
        documentation: RegisteredApplicationDocumentation.productivityLibrary
    )

    private let services: ProductivityLibraryApplicationServices

    init(services: ProductivityLibraryApplicationServices = .live) {
        self.services = services
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: ProductivityLibraryApplicationID.openTool,
                parentID: Self.id,
                title: "Open Productivity Library",
                subtitle: "Browse snippets, notes, Quicklinks, and emoji keywords",
                systemImage: "books.vertical",
                category: .productivity,
                keywords: ["open", "browse", "library", "snippets", "notes", "Quicklinks", "emoji"]
            ),
            makeCreateTool(
                id: ProductivityLibraryApplicationID.newSnippetTool,
                kind: .snippet,
                order: 1,
                keywords: ["new snippet", "create snippet", "text template", "clipboard template"]
            ),
            makeCreateTool(
                id: ProductivityLibraryApplicationID.newQuickNoteTool,
                kind: .quickNote,
                order: 2,
                keywords: ["new note", "create note", "quick note", "memo"]
            ),
            makeCreateTool(
                id: ProductivityLibraryApplicationID.newQuicklinkTool,
                kind: .quicklink,
                order: 3,
                keywords: ["new link", "create link", "Quicklink", "bookmark", "deep link"]
            ),
            makeCreateTool(
                id: ProductivityLibraryApplicationID.newEmojiKeywordTool,
                kind: .emojiKeyword,
                order: 4,
                keywords: ["new emoji keyword", "create emoji", "emoji shortcut", "emoji alias"]
            ),
            LauncherApplicationDefinition.tool(
                id: ProductivityLibraryApplicationID.newFloatingNoteTool,
                parentID: Self.id, title: "New Floating Note",
                subtitle: "Keep a note beside your work in its own window",
                systemImage: "note.text", category: .productivity, order: 5,
                keywords: ["floating note", "new note window", "sticky note", "memo"]
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(initialCreateKind: nil, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        let kind: ProductivityLibraryItemKind?
        switch toolID {
        case ProductivityLibraryApplicationID.newFloatingNoteTool:
            guard let floatingNotes = services.floatingNotes else {
                return .message("Floating notes are unavailable in this session.")
            }
            context.navigation.dismissLauncher()
            floatingNotes.newNote()
            return .message("Floating note opened.")
        case ProductivityLibraryApplicationID.openTool:
            kind = nil
        case ProductivityLibraryApplicationID.newSnippetTool:
            kind = .snippet
        case ProductivityLibraryApplicationID.newQuickNoteTool:
            kind = .quickNote
        case ProductivityLibraryApplicationID.newQuicklinkTool:
            kind = .quicklink
        case ProductivityLibraryApplicationID.newEmojiKeywordTool:
            kind = .emojiKeyword
        default:
            return .message("Productivity Library tool is unavailable.")
        }
        return makeLaunch(initialCreateKind: kind, context: context)
    }

    private func makeLaunch(
        initialCreateKind: ProductivityLibraryItemKind?,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let model = ProductivityLibraryViewModel(
            services: services,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher,
            initialCreateKind: initialCreateKind
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                ProductivityLibraryView(viewModel: $0)
            }
        )
    }

    private func makeCreateTool(
        id: CommandID,
        kind: ProductivityLibraryItemKind,
        order: Int,
        keywords: [String]
    ) -> LauncherApplicationDefinition {
        LauncherApplicationDefinition.tool(
            id: id,
            parentID: Self.id,
            title: "New \(kind.title)",
            subtitle: "Open a blank \(kind.title.lowercased()) editor",
            systemImage: kind.systemImage,
            category: .productivity,
            order: order,
            keywords: keywords
        )
    }
}
