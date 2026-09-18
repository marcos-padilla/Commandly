import Testing
@testable import MarkdownPreviewKit

@Suite("Markdown renderer syntax")
struct MarkdownRendererSyntaxTests {
    private let renderer = MarkdownRenderer()

    @Test("Headings, outline, paragraphs, inline syntax, and TOC render deterministically")
    func documentStructure() {
        let source = """
        # Project **Atlas**

        A paragraph with *emphasis*, **strength**, `code`, ~~old text~~, and :rocket:.

        ## Details

        ### Details
        """
        let result = renderer.render(source)
        #expect(result.outline == [
            MarkdownOutlineEntry(level: 1, title: "Project Atlas", anchor: "project-atlas"),
            MarkdownOutlineEntry(level: 2, title: "Details", anchor: "details"),
            MarkdownOutlineEntry(level: 3, title: "Details", anchor: "details-2"),
        ])
        #expect(result.html.contains("id=\"markdown-preview-toc\""))
        #expect(result.html.contains("<em>emphasis</em>"))
        #expect(result.html.contains("<strong>strength</strong>"))
        #expect(result.html.contains("<code class=\"inline-code\">code</code>"))
        #expect(result.html.contains("<del>old text</del>"))
        #expect(result.html.contains("🚀"))

        let hostResult = renderer.render(
            MarkdownRenderInput(markdown: source, emitsTableOfContents: false)
        )
        #expect(hostResult.outline == result.outline)
        #expect(!hostResult.html.contains("id=\"markdown-preview-toc\""))
    }

    @Test("Footnotes, mark, subscript, superscript, and automatic direction remain semantic")
    func extendedInlineSemantics() {
        let result = renderer.render("""
        نص ==highlight== H~2~O x^2^ with a note.[^safe]

        [^safe]: A bounded footnote.
        """)

        #expect(result.html.contains("dir=\"auto\""))
        #expect(result.html.contains("<mark>highlight</mark>"))
        #expect(result.html.contains("H<sub>2</sub>O"))
        #expect(result.html.contains("x<sup>2</sup>"))
        #expect(result.html.contains("aria-label=\"Footnotes\""))
        #expect(result.html.contains("id=\"footnote-safe\""))
        #expect(result.html.contains("href=\"#footnote-reference-safe\""))
    }

    @Test("YAML metadata, GFM table, tasks, alerts, and blockquotes render")
    func extendedBlocks() {
        let source = """
        ---
        title: Sample
        tags:
          - swift
          - markdown
        nested:
          owner: Commandly
        ---
        # Checklist

        | Item | State |
        | :--- | ---: |
        | Parser | Ready |

        - [x] Parse
        - [ ] Review

        > [!WARNING]
        > Keep input escaped.

        > A regular quote.
        """
        let result = renderer.render(source)
        #expect(result.frontMatter == [
            MarkdownFrontMatterEntry(key: "title", value: "Sample"),
            MarkdownFrontMatterEntry(key: "tags", value: "\nswift\nmarkdown"),
            MarkdownFrontMatterEntry(key: "nested", value: "\nowner: Commandly"),
        ])
        #expect(result.html.contains("<details class=\"front-matter\" open>"))
        #expect(result.html.contains("<table>"))
        #expect(result.html.contains("class=\"align-right\""))
        #expect(result.html.contains("<ul class=\"task-list\">"))
        #expect(result.html.contains("disabled checked"))
        #expect(result.html.contains("class=\"alert alert-warning\""))
        #expect(result.html.contains("<blockquote>A regular quote.</blockquote>"))

        let collapsed = renderer.render(
            "> [!NOTE]\n> Hidden alert.\n\n> Hidden quote.",
            configuration: MarkdownPreviewConfiguration(collapsesBlockquotes: true)
        ).html
        #expect(collapsed.contains("class=\"quote-details alert-details\""))
        #expect(collapsed.components(separatedBy: "class=\"quote-details").count == 3)
    }

    @Test("Fenced code and source use deterministic line-number hooks")
    func codeAndSourceLineNumbers() {
        let source = """
        ```swift
        let value = "<safe>"
        print(value)
        ```
        """
        let result = renderer.render(
            source,
            configuration: MarkdownPreviewConfiguration(
                codeTheme: .monokai,
                sourceViewMode: .source,
                showsLineNumbers: true
            )
        )
        #expect(result.html.contains("data-view=\"source\""))
        #expect(result.html.contains("id=\"markdown-preview-content\" data-preview-hook=\"content\" dir=\"auto\" hidden"))
        #expect(result.html.contains("id=\"markdown-preview-source\" data-preview-hook=\"source\" tabindex=\"0\" dir=\"auto\">"))
        #expect(result.html.contains("class=\"code-block language-swift\""))
        #expect(result.html.contains("<span class=\"syntax-keyword\">let</span>"))
        #expect(result.html.contains("<span class=\"syntax-string\">&quot;&lt;safe&gt;&quot;</span>"))
        #expect(result.html.contains("data-line=\"1\""))
        #expect(result.html.contains("&lt;safe&gt;"))
        #expect(result.html.contains("code-theme-monokai"))
    }

    @Test("Prepared documents retain their original text in source mode")
    func originalSource() {
        let result = renderer.render(
            MarkdownRenderInput(
                markdown: "```mermaid\ngraph TD; A-->B\n```",
                sourceMarkdown: "graph TD; A--&gt;B"
            ),
            configuration: MarkdownPreviewConfiguration(sourceViewMode: .source)
        )

        #expect(result.html.contains("graph TD; A--&amp;gt;B"))
        #expect(result.html.contains("data-diagram-kind=\"mermaid\""))
    }

    @Test("Math and Typst remain escaped styled notation")
    func mathAndTypst() {
        let source = """
        Inline $E = mc^2$.

        $$
        \\int_0^1 x dx
        $$

        ```typst
        $ sum_(i=1)^n i $
        ```
        """
        let html = renderer.render(source).html
        #expect(html.contains("class=\"math math-inline\""))
        #expect(html.contains("class=\"math math-display\""))
        #expect(html.contains("class=\"math typst-fallback\""))
        #expect(html.contains("Typst notation (text preview)"))

        let independentTypst = renderer.render(
            "```typst\n$ x^2 $\n```",
            configuration: MarkdownPreviewConfiguration(
                mathMode: .disabled,
                enablesMath: false,
                enablesTypst: true
            )
        ).html
        #expect(independentTypst.contains("Typst notation (text preview)"))
    }

    @Test("Safe subsets of Mermaid, Graphviz, and Vega render script-free SVG")
    func diagrams() {
        let source = """
        ```mermaid
        graph TD
        A[Start] --> B[Finish]
        ```

        ```dot
        digraph { Start -> Finish }
        ```

        ```vega-lite
        {"data":{"values":[{"kind":"A","count":2},{"kind":"B","count":5}]},"mark":"bar","encoding":{"x":{"field":"kind"},"y":{"field":"count"}}}
        ```
        """
        let html = renderer.render(source).html
        #expect(html.contains("data-diagram-kind=\"mermaid\""))
        #expect(html.contains("data-diagram-kind=\"graphviz\""))
        #expect(html.contains("data-diagram-kind=\"vega\""))
        #expect(html.components(separatedBy: "<svg role=\"img\"").count == 4)
        #expect(!html.contains("<foreignObject"))
    }

    @Test("Unsupported diagrams show an honest escaped fallback")
    func diagramFallback() {
        let html = renderer.render("""
        ```mermaid
        mindmap
          root((Ideas))
        ```
        """).html
        #expect(html.contains("diagram-fallback"))
        #expect(html.contains("outside the secure built-in preview subset"))
        #expect(html.contains("mindmap"))
    }

    @Test("Theme, sizing, print CSS, and view hooks are embedded without dependencies")
    func documentTemplate() {
        let configuration = MarkdownPreviewConfiguration(
            theme: .dark,
            codeTheme: .github,
            fontFamily: .serif,
            fontSize: 18,
            contentWidth: 1_020,
            initialZoom: 1.5
        )
        let html = renderer.render("# Title", configuration: configuration).html
        #expect(html.contains("--preview-zoom:1.500"))
        #expect(html.contains("--font-size:18.000px"))
        #expect(html.contains("--content-width:1020.000px"))
        #expect(html.contains("theme-dark code-theme-github font-serif"))
        #expect(html.contains("@media print"))
        #expect(html.contains("data-preview-hook=\"outline\""))
        #expect(html.contains("search-current"))
    }
}
