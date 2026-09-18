import Foundation

/// Inputs for one pure Markdown rendering operation.
public struct MarkdownRenderInput: Equatable, Sendable {
    /// Untrusted Markdown source to render.
    public let markdown: String
    /// Optional original text to expose in source mode when rendering uses a prepared wrapper.
    public let sourceMarkdown: String?
    /// Optional title for the generated HTML document.
    public let documentTitle: String?
    /// Relative Markdown image reference to a host-validated `data:` URL.
    public let localImageDataURLs: [String: String]
    /// Optional host override for emitting an in-document table of contents.
    ///
    /// Hosts with native outline chrome can suppress the duplicate HTML outline while still
    /// receiving parsed `MarkdownOutlineEntry` values in the render result.
    public let emitsTableOfContents: Bool?

    /// Creates one render request.
    public init(
        markdown: String,
        sourceMarkdown: String? = nil,
        documentTitle: String? = nil,
        localImageDataURLs: [String: String] = [:],
        emitsTableOfContents: Bool? = nil
    ) {
        self.markdown = markdown
        self.sourceMarkdown = sourceMarkdown
        self.documentTitle = documentTitle
        self.localImageDataURLs = localImageDataURLs
        self.emitsTableOfContents = emitsTableOfContents
    }
}

/// One navigable heading in a rendered document.
public struct MarkdownOutlineEntry: Codable, Equatable, Sendable {
    /// Heading depth from one through six.
    public let level: Int
    /// Plain-text heading title.
    public let title: String
    /// Unique same-document anchor without a leading hash.
    public let anchor: String

    /// Creates a bounded outline entry.
    public init(level: Int, title: String, anchor: String) {
        self.level = min(max(level, 1), 6)
        self.title = title
        self.anchor = anchor
    }
}

/// One top-level YAML front-matter field.
public struct MarkdownFrontMatterEntry: Codable, Equatable, Sendable {
    /// Top-level YAML key.
    public let key: String
    /// Plain-text scalar or newline-joined nested value.
    public let value: String

    /// Creates one parsed metadata entry.
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Fully self-contained rendering output suitable for a nonpersistent web view or HTML export.
public struct MarkdownRenderedDocument: Equatable, Sendable {
    /// Complete HTML document including CSP, styles, and audited interaction hooks.
    public let html: String
    /// Ordered headings discovered during parsing.
    public let outline: [MarkdownOutlineEntry]
    /// Ordered top-level YAML metadata discovered at the start of the source.
    public let frontMatter: [MarkdownFrontMatterEntry]

    /// Creates a complete rendering result.
    public init(
        html: String,
        outline: [MarkdownOutlineEntry],
        frontMatter: [MarkdownFrontMatterEntry]
    ) {
        self.html = html
        self.outline = outline
        self.frontMatter = frontMatter
    }
}

/// Stable element identifiers that hosts may use with native zoom, search, and navigation APIs.
public enum MarkdownHTMLHooks {
    /// Element ID for parsed content.
    public static let contentElementID = "markdown-preview-content"
    /// Element ID for the generated heading outline.
    public static let tableOfContentsElementID = "markdown-preview-toc"
    /// Element ID for escaped source content.
    public static let sourceElementID = "markdown-preview-source"
    /// Nonce used exclusively by the renderer-owned interaction script.
    public static let scriptNonce = "commandly-markdown-preview"
    /// CSP emitted by every rendered document.
    public static let contentSecurityPolicy = "default-src 'none'; script-src 'nonce-commandly-markdown-preview'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; manifest-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; navigate-to 'none'"
}
