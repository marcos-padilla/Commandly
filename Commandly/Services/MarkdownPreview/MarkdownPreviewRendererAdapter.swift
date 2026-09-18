import Foundation
import MarkdownPreviewKit

nonisolated protocol MarkdownPreviewRendering: Sendable {
    func render(
        source: MarkdownPreviewLoadedSource,
        configuration: MarkdownPreviewConfiguration
    ) async -> MarkdownRenderedDocument
}

/// Keeps the package's synchronous, pure rendering work off the main actor.
actor MarkdownPreviewRendererAdapter: MarkdownPreviewRendering {
    private let renderer: MarkdownRenderer

    init(renderer: MarkdownRenderer = MarkdownRenderer()) {
        self.renderer = renderer
    }

    func render(
        source: MarkdownPreviewLoadedSource,
        configuration: MarkdownPreviewConfiguration
    ) async -> MarkdownRenderedDocument {
        renderer.render(
            MarkdownRenderInput(
                markdown: MarkdownPreviewFileTypes.preparingForPreview(
                    source.markdown,
                    fileExtension: source.sourceURL.pathExtension
                ),
                sourceMarkdown: source.markdown,
                documentTitle: source.displayName,
                localImageDataURLs: source.localImageDataURLs,
                emitsTableOfContents: false
            ),
            configuration: configuration
        )
    }
}
