import CommandKit
import Foundation

/// Static documentation for behavior that is part of Commandly itself rather than a registered app.
struct CoreDocumentationArticle: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let category: DocumentationCategory
    let order: Int
    let documentation: LauncherApplicationDocumentation
}

/// A documentation article resolved with current application preferences and command metadata.
struct DocumentationArticle: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case core
        case application(CommandID)
    }

    let id: String
    let source: Source
    let title: String
    let subtitle: String?
    let systemImage: String
    let category: DocumentationCategory
    let order: Int
    let documentation: LauncherApplicationDocumentation
    let alias: String?
    let globalHotKey: String?
    let isEnabled: Bool
    let defaultActions: [CommandActionDescriptor]
    let configurationFields: [LauncherConfigurationField]
    let searchableText: String

    var applicationID: CommandID? {
        guard case .application(let id) = source else { return nil }
        return id
    }

    var statusLabel: String? {
        guard case .application = source else { return nil }
        return isEnabled ? "Installed" : "Disabled"
    }
}

/// Builds the user-facing catalog from core articles and the live launcher application registry.
@MainActor
enum DocumentationCatalog {
    static func articles(
        registry: LauncherApplicationRegistry,
        coreArticles: [CoreDocumentationArticle] = CoreDocumentationCatalog.articles
    ) -> [DocumentationArticle] {
        let core = coreArticles.map { article in
            makeArticle(
                id: article.id,
                source: .core,
                title: article.title,
                subtitle: article.subtitle,
                systemImage: article.systemImage,
                category: article.category,
                order: article.order,
                documentation: article.documentation,
                alias: nil,
                globalHotKey: nil,
                isEnabled: true,
                defaultActions: [],
                configurationFields: []
            )
        }

        let applications = registry.allDefinitions().compactMap { definition -> DocumentationArticle? in
            guard let documentation = definition.documentation,
                  registry.application(for: definition.id) != nil else {
                return nil
            }
            let settings = registry.resolvedSettings(for: definition.id)
            return makeArticle(
                id: "application.\(definition.id.rawValue)",
                source: .application(definition.id),
                title: definition.title,
                subtitle: definition.subtitle,
                systemImage: definition.systemImage,
                category: documentation.category,
                order: 1_000 + definition.order,
                documentation: documentation,
                alias: settings?.alias.nilIfEmpty,
                globalHotKey: settings?.hotKey?.displayTitle,
                isEnabled: registry.isEffectivelyEnabled(definition.id),
                defaultActions: definition.commandManifest?.defaultActions ?? [],
                configurationFields: definition.configurationFields
            )
        }

        return (core + applications).sorted(by: sortArticles)
    }

    private static func makeArticle(
        id: String,
        source: DocumentationArticle.Source,
        title: String,
        subtitle: String?,
        systemImage: String,
        category: DocumentationCategory,
        order: Int,
        documentation: LauncherApplicationDocumentation,
        alias: String?,
        globalHotKey: String?,
        isEnabled: Bool,
        defaultActions: [CommandActionDescriptor],
        configurationFields: [LauncherConfigurationField]
    ) -> DocumentationArticle {
        let searchValues = [
            title,
            subtitle,
            documentation.overview,
            documentation.keywords.joined(separator: " "),
            alias,
            globalHotKey,
            defaultActions.map { action in
                [action.title, action.keyHint?.symbols.joined(separator: "")]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: " "),
            configurationFields.map { field in
                [field.title, field.description, field.placeholder]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: " "),
            searchableText(for: documentation),
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .foldedForDocumentationSearch

        return DocumentationArticle(
            id: id,
            source: source,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            category: category,
            order: order,
            documentation: documentation,
            alias: alias,
            globalHotKey: globalHotKey,
            isEnabled: isEnabled,
            defaultActions: defaultActions,
            configurationFields: configurationFields,
            searchableText: searchValues
        )
    }

    private static func searchableText(
        for documentation: LauncherApplicationDocumentation
    ) -> String {
        documentation.sections.flatMap { section in
            [section.title] + section.blocks.flatMap { block -> [String] in
                switch block.content {
                case .paragraph(let text):
                    return [text]
                case .bullets(let items), .steps(let items):
                    return items
                case .shortcuts(let shortcuts):
                    return shortcuts.flatMap { shortcut in
                        [shortcut.title, shortcut.keys.joined(separator: " "), shortcut.detail]
                            .compactMap { $0 }
                    }
                case .examples(let examples):
                    return examples.flatMap { example in
                        [example.input, example.output, example.detail].compactMap { $0 }
                    }
                case .callout(let callout):
                    return [callout.title, callout.text, callout.kind.rawValue]
                }
            }
        }.joined(separator: " ")
    }

    private static func sortArticles(
        _ left: DocumentationArticle,
        _ right: DocumentationArticle
    ) -> Bool {
        if left.category.order != right.category.order {
            return left.category.order < right.category.order
        }
        if left.order != right.order { return left.order < right.order }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}

extension String {
    fileprivate var foldedForDocumentationSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

