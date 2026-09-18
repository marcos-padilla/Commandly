import Testing
@testable import MarkdownPreviewKit

@Suite("Markdown renderer security")
struct MarkdownRendererSecurityTests {
    private let renderer = MarkdownRenderer()

    @Test("Raw HTML, scripts, event handlers, and unsafe links never execute")
    func escapesUntrustedMarkup() {
        let source = """
        # <img src=x onerror="alert(1)">
        <script>window.pwned = true</script>
        [Run](javascript:alert(1))
        ![Tracker](https://example.invalid/pixel.png)
        """
        let result = renderer.render(
            source,
            documentTitle: "</title><script>bad()</script>"
        )

        #expect(result.html.contains("&lt;img src=x onerror=&quot;alert(1)&quot;&gt;"))
        #expect(result.html.contains("&lt;script&gt;window.pwned = true&lt;/script&gt;"))
        #expect(result.html.contains("<span class=\"blocked-link\">Run</span>"))
        #expect(result.html.contains("aria-label=\"Image unavailable\">Tracker</span>"))
        #expect(!result.html.contains("src=\"https://example.invalid"))
        #expect(!result.html.contains("<script>bad()"))
        #expect(result.html.components(separatedBy: "<script nonce=").count == 2)
    }

    @Test("Document carries an offline restrictive CSP and audited hooks")
    func contentSecurityPolicy() {
        let html = renderer.render("Safe").html
        #expect(html.contains("default-src &#39;none&#39;; script-src &#39;nonce-commandly-markdown-preview&#39;"))
        #expect(html.contains("script-src &#39;nonce-\(MarkdownHTMLHooks.scriptNonce)&#39;"))
        #expect(html.contains("connect-src &#39;none&#39;"))
        #expect(html.contains("form-action &#39;none&#39;"))
        #expect(html.contains("img-src data:"))
        #expect(html.contains("Object.defineProperty(window,\"commandlyMarkdown\""))
        #expect(html.contains("setSourceVisible"))
        #expect(html.contains("scrollToAnchor"))
        #expect(html.contains("setZoom"))
        #expect(html.contains("function search("))
        #expect(html.contains("clearSearch"))
        #expect(html.contains("prefers-reduced-motion:reduce"))
        #expect(html.contains("scrollBehavior()"))
    }

    @Test("Only safe links and traversal-free Markdown relatives remain interactive")
    func linkPolicy() {
        let source = """
        [Web](https://example.com/docs)
        [Mail](mailto:help@example.com)
        [Anchor](#part-one)
        [Guide](guides/start.md#install)
        [Dot guide](./guides/start.md#install)
        [Reference guide][guide]
        [Traversal](..%2Fsecret.md)
        [Double traversal](%252e%252e%252Fsecret.md)
        [File](file:///tmp/note.md)
        [Script](JaVaScRiPt:alert(1))

        [guide]: ./guides/start.md#install "Local guide"
        """
        let html = renderer.render(source).html
        #expect(html.contains("href=\"https://example.com/docs\""))
        #expect(html.contains("href=\"mailto:help@example.com\""))
        #expect(html.contains("href=\"#part-one\""))
        #expect(html.contains("href=\"guides/start.md#install\""))
        #expect(html.components(separatedBy: "href=\"guides/start.md#install\"").count == 4)
        #expect(!html.contains("href=\"..%2Fsecret.md\""))
        #expect(!html.contains("href=\"%252e%252e%252Fsecret.md\""))
        #expect(!html.contains("href=\"file:"))
        #expect(!html.lowercased().contains("href=\"javascript:"))

        let disabled = renderer.render(
            "[Web](https://example.com)",
            configuration: MarkdownPreviewConfiguration(linkPolicy: .disabled)
        ).html
        #expect(!disabled.contains("href=\"https://example.com\""))
    }

    @Test("Images resolve only through bounded embedded data mappings")
    func imagePolicy() {
        let png = "data:image/png;base64,iVBORw0KGgo="
        let source = """
        ![Local](./assets/icon%20one.png "Preview")
        ![Angle](<assets/icon one.png>)
        ![Remote](https://example.com/image.png)
        ![Traversal](../private.png)
        ![SVG](data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=)
        ![Inline](data:image/png;base64,iVBORw0KGgo=)
        """
        let result = renderer.render(
            MarkdownRenderInput(
                markdown: source,
                localImageDataURLs: ["assets/icon one.png": png]
            )
        )
        #expect(result.html.contains("src=\"\(png)\" alt=\"Local\""))
        #expect(result.html.contains("src=\"\(png)\" alt=\"Angle\""))
        #expect(!result.html.contains("src=\"https://example.com/image.png"))
        #expect(!result.html.contains("src=\"data:image/svg+xml"))
        #expect(result.html.components(separatedBy: "src=\"\(png)\"").count == 3)
        #expect(result.html.components(separatedBy: "Image unavailable").count == 5)

        let disabled = renderer.render(
            MarkdownRenderInput(markdown: "![Local](assets/icon.png)", localImageDataURLs: ["assets/icon.png": png]),
            configuration: MarkdownPreviewConfiguration(imagePolicy: .disabled)
        )
        #expect(!disabled.html.contains("src=\"data:image/png"))
    }
}
