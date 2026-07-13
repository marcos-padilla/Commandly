import Foundation

/// A broad section used to group articles in Commandly's documentation browser.
enum DocumentationCategory: String, CaseIterable, Identifiable, Sendable {
    case gettingStarted
    case coreFeatures
    case productivity
    case system
    case utilities
    case settingsAndPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .coreFeatures: return "Core Features"
        case .productivity: return "Productivity"
        case .system: return "System"
        case .utilities: return "Utilities"
        case .settingsAndPrivacy: return "Settings & Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: return "sparkles"
        case .coreFeatures: return "command"
        case .productivity: return "square.grid.2x2"
        case .system: return "macbook"
        case .utilities: return "wrench.and.screwdriver"
        case .settingsAndPrivacy: return "gearshape"
        }
    }

    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// Authored, UI-neutral help content contributed by a launcher application.
struct LauncherApplicationDocumentation: Equatable, Sendable {
    let category: DocumentationCategory
    let overview: String
    let sections: [DocumentationSection]
    let keywords: [String]

    init(
        category: DocumentationCategory,
        overview: String,
        sections: [DocumentationSection],
        keywords: [String] = []
    ) {
        self.category = category
        self.overview = overview
        self.sections = sections
        self.keywords = keywords
    }
}

/// A stable, linkable section inside a documentation article.
struct DocumentationSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let blocks: [DocumentationBlock]

    init(id: String, title: String, blocks: [DocumentationBlock]) {
        self.id = id
        self.title = title
        self.blocks = blocks
    }
}

/// A structured block rendered by the documentation article view.
struct DocumentationBlock: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case paragraph(String)
        case bullets([String])
        case steps([String])
        case shortcuts([DocumentationShortcut])
        case examples([DocumentationExample])
        case callout(DocumentationCallout)
    }

    let id: String
    let content: Content

    static func paragraph(_ id: String, _ text: String) -> DocumentationBlock {
        DocumentationBlock(id: id, content: .paragraph(text))
    }

    static func bullets(_ id: String, _ items: [String]) -> DocumentationBlock {
        DocumentationBlock(id: id, content: .bullets(items))
    }

    static func steps(_ id: String, _ items: [String]) -> DocumentationBlock {
        DocumentationBlock(id: id, content: .steps(items))
    }

    static func shortcuts(
        _ id: String,
        _ items: [DocumentationShortcut]
    ) -> DocumentationBlock {
        DocumentationBlock(id: id, content: .shortcuts(items))
    }

    static func examples(
        _ id: String,
        _ items: [DocumentationExample]
    ) -> DocumentationBlock {
        DocumentationBlock(id: id, content: .examples(items))
    }

    static func callout(_ id: String, _ callout: DocumentationCallout) -> DocumentationBlock {
        DocumentationBlock(id: id, content: .callout(callout))
    }
}

/// A keyboard action shown as human-readable key caps and supporting detail.
struct DocumentationShortcut: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let keys: [String]
    let detail: String?

    init(id: String, title: String, keys: [String], detail: String? = nil) {
        self.id = id
        self.title = title
        self.keys = keys
        self.detail = detail
    }
}

/// A concrete input/output recipe, especially useful for calculator and transformation tools.
struct DocumentationExample: Identifiable, Equatable, Sendable {
    let id: String
    let input: String
    let output: String?
    let detail: String?

    init(id: String, input: String, output: String? = nil, detail: String? = nil) {
        self.id = id
        self.input = input
        self.output = output
        self.detail = detail
    }
}

enum DocumentationCalloutKind: String, Equatable, Sendable {
    case tip
    case privacy
    case permission
    case limitation
    case important
}

/// A visually distinct note whose meaning is also conveyed by its label and icon.
struct DocumentationCallout: Equatable, Sendable {
    let kind: DocumentationCalloutKind
    let title: String
    let text: String

    init(kind: DocumentationCalloutKind, title: String, text: String) {
        self.kind = kind
        self.title = title
        self.text = text
    }
}

