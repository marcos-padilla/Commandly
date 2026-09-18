import Foundation

/// Color treatment applied to a rendered Markdown document.
public enum MarkdownTheme: String, Codable, CaseIterable, Sendable {
    /// Follow the host operating-system appearance.
    case system
    /// Use a cool light canvas.
    case light
    /// Use a low-luminance canvas.
    case dark
    /// Use a warm reading canvas.
    case paper
}

/// Color treatment applied to fenced and inline code.
public enum MarkdownCodeTheme: String, Codable, CaseIterable, Sendable {
    /// Adapt code colors to the selected document theme.
    case adaptive
    /// Use a familiar neutral repository-style palette.
    case github
    /// Use a high-contrast dark palette inspired by classic editors.
    case monokai
    /// Use a muted dark palette suitable for long code samples.
    case atomOneDark
    /// Use Commandly's neutral graphite palette.
    case graphite
    /// Use a deep blue palette.
    case ocean
    /// Use a violet low-light palette.
    case dusk
    /// Use a warm light code palette.
    case paper
}

/// Font family used for prose in a preview.
public enum MarkdownFontFamily: String, Codable, CaseIterable, Sendable {
    /// Use the native system interface family.
    case system
    /// Use the platform serif reading family.
    case serif
    /// Use the platform monospaced family for all content.
    case monospaced
}

/// The document representation produced by the renderer.
public enum SourceViewMode: String, Codable, CaseIterable, Sendable {
    /// Display parsed Markdown.
    case rendered
    /// Display escaped Markdown source.
    case source
}

/// Which Markdown links remain interactive.
public enum MarkdownLinkPolicy: String, Codable, CaseIterable, Sendable {
    /// Render all links as non-interactive text.
    case disabled
    /// Permit same-document anchors plus HTTP, HTTPS, and email links.
    case webAndEmail
    /// Also permit traversal-free relative links to another supported Markdown file.
    case webEmailAndRelativeMarkdown
}

/// Which images may be emitted by the renderer.
public enum MarkdownImagePolicy: String, Codable, CaseIterable, Sendable {
    /// Replace images with accessible text placeholders.
    case disabled
    /// Permit only validated `data:` images supplied by the host or present in the source.
    case embeddedDataOnly
}

/// How dependency-free diagram blocks are represented.
public enum DiagramRenderingMode: String, Codable, CaseIterable, Sendable {
    /// Preserve all diagram blocks as escaped code.
    case disabled
    /// Render the supported safe subset as SVG and show an honest source fallback otherwise.
    case safePreview
}

/// How mathematical notation is represented without a script engine.
public enum MathRenderingMode: String, Codable, CaseIterable, Sendable {
    /// Preserve math delimiters as ordinary text.
    case disabled
    /// Preserve notation in a typographically distinct, escaped text treatment.
    case styledText
}

/// Shared, non-secret settings used by the Commandly app and its Quick Look extension.
///
/// Numeric values are clamped to bounds that keep app and extension rendering predictable.
/// Decoding is tolerant of missing or future enum values and restores safe defaults.
public struct MarkdownPreviewConfiguration: Codable, Equatable, Sendable {
    /// Supported prose font-size bounds in points.
    public static let fontSizeRange = 12.0 ... 24.0
    /// Supported compact-preview font-size bounds in points.
    public static let finderFontSizeRange = 10.0 ... 24.0
    /// Supported unitless line-height bounds.
    public static let lineHeightRange = 1.2 ... 2.2
    /// Supported content-column width bounds in CSS pixels.
    public static let contentWidthRange = 480.0 ... 1_400.0
    /// Supported page zoom bounds.
    public static let zoomRange = 0.5 ... 3.0
    /// Supported tab widths in spaces.
    public static let tabWidthRange = 2 ... 8

    /// Document color treatment.
    public let theme: MarkdownTheme
    /// Fenced and inline code color treatment.
    public let codeTheme: MarkdownCodeTheme
    /// Prose font family.
    public let fontFamily: MarkdownFontFamily
    /// Initially visible document representation.
    public let sourceViewMode: SourceViewMode
    /// Interactive-link policy.
    public let linkPolicy: MarkdownLinkPolicy
    /// Image emission policy.
    public let imagePolicy: MarkdownImagePolicy
    /// Diagram rendering policy.
    public let diagramMode: DiagramRenderingMode
    /// Mathematical notation rendering policy.
    public let mathMode: MathRenderingMode

    /// Prose font size in points.
    public let fontSize: Double
    /// Compact font size used by Finder Quick Look surfaces.
    public let finderFontSize: Double
    /// Alias for hosts that describe Finder Quick Look as a compact preview.
    public var compactFontSize: Double { finderFontSize }
    /// Unitless prose line height.
    public let lineHeight: Double
    /// Maximum reading-column width in CSS pixels.
    public let contentWidth: Double
    /// Initial page zoom multiplier.
    public let initialZoom: Double
    /// Tab width in spaces for code and source.
    public let tabWidth: Int

    /// Whether a heading outline is emitted as a table of contents.
    public let showsTableOfContents: Bool
    /// Whether parsed YAML metadata is shown above the document.
    public let rendersFrontMatter: Bool
    /// Whether GFM tables are enabled.
    public let enablesTables: Bool
    /// Whether GFM task checkboxes are enabled.
    public let enablesTaskLists: Bool
    /// Whether GFM strikethrough is enabled.
    public let enablesStrikethrough: Bool
    /// Whether GitHub-style alert blockquotes are enabled.
    public let enablesAlerts: Bool
    /// Whether recognized colon emoji codes are replaced.
    public let enablesEmoji: Bool
    /// Whether dollar-delimited math is recognized.
    public let enablesMath: Bool
    /// Whether Typst fences receive a styled notation fallback.
    public let enablesTypst: Bool
    /// Whether the safe Mermaid subset may render as SVG.
    public let enablesMermaid: Bool
    /// Whether the safe Graphviz subset may render as SVG.
    public let enablesGraphviz: Bool
    /// Whether the safe Vega bar-chart subset may render as SVG.
    public let enablesVega: Bool
    /// Whether code and source lines receive visible line numbers.
    public let showsLineNumbers: Bool
    /// Whether ordinary Markdown soft breaks become HTML breaks.
    public let softBreaksAsLineBreaks: Bool
    /// Whether ordinary blockquotes begin inside collapsed disclosure controls.
    public let collapsesBlockquotes: Bool
    /// Host preference for reloading a changed open file.
    public let automaticallyReloads: Bool
    /// Host preference for restoring per-file scroll position.
    public let remembersScrollPosition: Bool

    /// Recommended settings for a new installation.
    public static let `default` = MarkdownPreviewConfiguration()

    /// Creates a sanitized shared preview configuration.
    public init(
        theme: MarkdownTheme = .system,
        codeTheme: MarkdownCodeTheme = .adaptive,
        fontFamily: MarkdownFontFamily = .system,
        sourceViewMode: SourceViewMode = .rendered,
        linkPolicy: MarkdownLinkPolicy = .webEmailAndRelativeMarkdown,
        imagePolicy: MarkdownImagePolicy = .embeddedDataOnly,
        diagramMode: DiagramRenderingMode = .safePreview,
        mathMode: MathRenderingMode = .styledText,
        fontSize: Double = 14,
        finderFontSize: Double = 13,
        lineHeight: Double = 1.6,
        contentWidth: Double = 860,
        initialZoom: Double = 1,
        tabWidth: Int = 4,
        showsTableOfContents: Bool = true,
        rendersFrontMatter: Bool = true,
        enablesTables: Bool = true,
        enablesTaskLists: Bool = true,
        enablesStrikethrough: Bool = true,
        enablesAlerts: Bool = true,
        enablesEmoji: Bool = true,
        enablesMath: Bool = true,
        enablesTypst: Bool = true,
        enablesMermaid: Bool = true,
        enablesGraphviz: Bool = true,
        enablesVega: Bool = true,
        showsLineNumbers: Bool = false,
        softBreaksAsLineBreaks: Bool = false,
        collapsesBlockquotes: Bool = false,
        automaticallyReloads: Bool = true,
        remembersScrollPosition: Bool = true
    ) {
        self.theme = theme
        self.codeTheme = codeTheme
        self.fontFamily = fontFamily
        self.sourceViewMode = sourceViewMode
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
        self.diagramMode = diagramMode
        self.mathMode = mathMode
        self.fontSize = Self.clamp(fontSize, to: Self.fontSizeRange, fallback: 14)
        self.finderFontSize = Self.clamp(finderFontSize, to: Self.finderFontSizeRange, fallback: 13)
        self.lineHeight = Self.clamp(lineHeight, to: Self.lineHeightRange, fallback: 1.6)
        self.contentWidth = Self.clamp(contentWidth, to: Self.contentWidthRange, fallback: 860)
        self.initialZoom = Self.clamp(initialZoom, to: Self.zoomRange, fallback: 1)
        self.tabWidth = min(max(tabWidth, Self.tabWidthRange.lowerBound), Self.tabWidthRange.upperBound)
        self.showsTableOfContents = showsTableOfContents
        self.rendersFrontMatter = rendersFrontMatter
        self.enablesTables = enablesTables
        self.enablesTaskLists = enablesTaskLists
        self.enablesStrikethrough = enablesStrikethrough
        self.enablesAlerts = enablesAlerts
        self.enablesEmoji = enablesEmoji
        self.enablesMath = enablesMath
        self.enablesTypst = enablesTypst
        self.enablesMermaid = enablesMermaid
        self.enablesGraphviz = enablesGraphviz
        self.enablesVega = enablesVega
        self.showsLineNumbers = showsLineNumbers
        self.softBreaksAsLineBreaks = softBreaksAsLineBreaks
        self.collapsesBlockquotes = collapsesBlockquotes
        self.automaticallyReloads = automaticallyReloads
        self.remembersScrollPosition = remembersScrollPosition
    }

    /// Returns the same settings after applying all documented numeric bounds.
    public func sanitized() -> MarkdownPreviewConfiguration {
        MarkdownPreviewConfiguration(
            theme: theme,
            codeTheme: codeTheme,
            fontFamily: fontFamily,
            sourceViewMode: sourceViewMode,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy,
            diagramMode: diagramMode,
            mathMode: mathMode,
            fontSize: fontSize,
            finderFontSize: finderFontSize,
            lineHeight: lineHeight,
            contentWidth: contentWidth,
            initialZoom: initialZoom,
            tabWidth: tabWidth,
            showsTableOfContents: showsTableOfContents,
            rendersFrontMatter: rendersFrontMatter,
            enablesTables: enablesTables,
            enablesTaskLists: enablesTaskLists,
            enablesStrikethrough: enablesStrikethrough,
            enablesAlerts: enablesAlerts,
            enablesEmoji: enablesEmoji,
            enablesMath: enablesMath,
            enablesTypst: enablesTypst,
            enablesMermaid: enablesMermaid,
            enablesGraphviz: enablesGraphviz,
            enablesVega: enablesVega,
            showsLineNumbers: showsLineNumbers,
            softBreaksAsLineBreaks: softBreaksAsLineBreaks,
            collapsesBlockquotes: collapsesBlockquotes,
            automaticallyReloads: automaticallyReloads,
            remembersScrollPosition: remembersScrollPosition
        )
    }

    /// Returns the same renderer settings with Finder's compact font size as the prose size.
    public func usingFinderFontSize() -> MarkdownPreviewConfiguration {
        MarkdownPreviewConfiguration(
            theme: theme,
            codeTheme: codeTheme,
            fontFamily: fontFamily,
            sourceViewMode: sourceViewMode,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy,
            diagramMode: diagramMode,
            mathMode: mathMode,
            fontSize: finderFontSize,
            finderFontSize: finderFontSize,
            lineHeight: lineHeight,
            contentWidth: contentWidth,
            initialZoom: initialZoom,
            tabWidth: tabWidth,
            showsTableOfContents: showsTableOfContents,
            rendersFrontMatter: rendersFrontMatter,
            enablesTables: enablesTables,
            enablesTaskLists: enablesTaskLists,
            enablesStrikethrough: enablesStrikethrough,
            enablesAlerts: enablesAlerts,
            enablesEmoji: enablesEmoji,
            enablesMath: enablesMath,
            enablesTypst: enablesTypst,
            enablesMermaid: enablesMermaid,
            enablesGraphviz: enablesGraphviz,
            enablesVega: enablesVega,
            showsLineNumbers: showsLineNumbers,
            softBreaksAsLineBreaks: softBreaksAsLineBreaks,
            collapsesBlockquotes: collapsesBlockquotes,
            automaticallyReloads: automaticallyReloads,
            remembersScrollPosition: remembersScrollPosition
        )
    }

    /// Decodes a version-tolerant configuration and sanitizes all numeric fields.
    public init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            theme: container.decodeSafely(MarkdownTheme.self, forKey: .theme) ?? defaults.theme,
            codeTheme: container.decodeSafely(MarkdownCodeTheme.self, forKey: .codeTheme) ?? defaults.codeTheme,
            fontFamily: container.decodeSafely(MarkdownFontFamily.self, forKey: .fontFamily) ?? defaults.fontFamily,
            sourceViewMode: container.decodeSafely(SourceViewMode.self, forKey: .sourceViewMode) ?? defaults.sourceViewMode,
            linkPolicy: container.decodeSafely(MarkdownLinkPolicy.self, forKey: .linkPolicy) ?? defaults.linkPolicy,
            imagePolicy: container.decodeSafely(MarkdownImagePolicy.self, forKey: .imagePolicy) ?? defaults.imagePolicy,
            diagramMode: container.decodeSafely(DiagramRenderingMode.self, forKey: .diagramMode) ?? defaults.diagramMode,
            mathMode: container.decodeSafely(MathRenderingMode.self, forKey: .mathMode) ?? defaults.mathMode,
            fontSize: container.decodeSafely(Double.self, forKey: .fontSize) ?? defaults.fontSize,
            finderFontSize: container.decodeSafely(Double.self, forKey: .finderFontSize) ?? defaults.finderFontSize,
            lineHeight: container.decodeSafely(Double.self, forKey: .lineHeight) ?? defaults.lineHeight,
            contentWidth: container.decodeSafely(Double.self, forKey: .contentWidth) ?? defaults.contentWidth,
            initialZoom: container.decodeSafely(Double.self, forKey: .initialZoom) ?? defaults.initialZoom,
            tabWidth: container.decodeSafely(Int.self, forKey: .tabWidth) ?? defaults.tabWidth,
            showsTableOfContents: container.decodeSafely(Bool.self, forKey: .showsTableOfContents) ?? defaults.showsTableOfContents,
            rendersFrontMatter: container.decodeSafely(Bool.self, forKey: .rendersFrontMatter) ?? defaults.rendersFrontMatter,
            enablesTables: container.decodeSafely(Bool.self, forKey: .enablesTables) ?? defaults.enablesTables,
            enablesTaskLists: container.decodeSafely(Bool.self, forKey: .enablesTaskLists) ?? defaults.enablesTaskLists,
            enablesStrikethrough: container.decodeSafely(Bool.self, forKey: .enablesStrikethrough) ?? defaults.enablesStrikethrough,
            enablesAlerts: container.decodeSafely(Bool.self, forKey: .enablesAlerts) ?? defaults.enablesAlerts,
            enablesEmoji: container.decodeSafely(Bool.self, forKey: .enablesEmoji) ?? defaults.enablesEmoji,
            enablesMath: container.decodeSafely(Bool.self, forKey: .enablesMath) ?? defaults.enablesMath,
            enablesTypst: container.decodeSafely(Bool.self, forKey: .enablesTypst) ?? defaults.enablesTypst,
            enablesMermaid: container.decodeSafely(Bool.self, forKey: .enablesMermaid) ?? defaults.enablesMermaid,
            enablesGraphviz: container.decodeSafely(Bool.self, forKey: .enablesGraphviz) ?? defaults.enablesGraphviz,
            enablesVega: container.decodeSafely(Bool.self, forKey: .enablesVega) ?? defaults.enablesVega,
            showsLineNumbers: container.decodeSafely(Bool.self, forKey: .showsLineNumbers) ?? defaults.showsLineNumbers,
            softBreaksAsLineBreaks: container.decodeSafely(Bool.self, forKey: .softBreaksAsLineBreaks) ?? defaults.softBreaksAsLineBreaks,
            collapsesBlockquotes: container.decodeSafely(Bool.self, forKey: .collapsesBlockquotes) ?? defaults.collapsesBlockquotes,
            automaticallyReloads: container.decodeSafely(Bool.self, forKey: .automaticallyReloads) ?? defaults.automaticallyReloads,
            remembersScrollPosition: container.decodeSafely(Bool.self, forKey: .remembersScrollPosition) ?? defaults.remembersScrollPosition
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension KeyedDecodingContainer {
    func decodeSafely<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}
