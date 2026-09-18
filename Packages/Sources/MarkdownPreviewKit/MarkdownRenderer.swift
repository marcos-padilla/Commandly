import Foundation

/// Dependency-free, offline Markdown-to-HTML renderer shared by app and extension surfaces.
public struct MarkdownRenderer: Sendable {
    /// Creates a stateless renderer.
    public init() {}

    /// Renders one input into a self-contained HTML document.
    ///
    /// The operation is pure and nonthrowing. Unsupported syntax is escaped and preserved rather
    /// than interpreted. Hosts should still use a nonpersistent web view and deny top-level
    /// navigation except for explicitly handled links.
    public func render(
        _ input: MarkdownRenderInput,
        configuration: MarkdownPreviewConfiguration = .default
    ) -> MarkdownRenderedDocument {
        let safeConfiguration = configuration.sanitized()
        var parser = MarkdownParser(
            configuration: safeConfiguration,
            localImageDataURLs: input.localImageDataURLs
        )
        let parsed = parser.parse(input.markdown)
        let html = MarkdownDocumentTemplate.make(
            input: input,
            configuration: safeConfiguration,
            parsed: parsed
        )
        return MarkdownRenderedDocument(
            html: html,
            outline: parsed.outline,
            frontMatter: parsed.frontMatter
        )
    }

    /// Convenience overload for callers without a prebuilt input value.
    public func render(
        _ markdown: String,
        configuration: MarkdownPreviewConfiguration = .default,
        documentTitle: String? = nil,
        localImageDataURLs: [String: String] = [:]
    ) -> MarkdownRenderedDocument {
        render(
            MarkdownRenderInput(
                markdown: markdown,
                documentTitle: documentTitle,
                localImageDataURLs: localImageDataURLs
            ),
            configuration: configuration
        )
    }
}
