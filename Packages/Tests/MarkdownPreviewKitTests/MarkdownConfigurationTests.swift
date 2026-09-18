import Foundation
import Testing
@testable import MarkdownPreviewKit

@Suite("Markdown preview configuration", .serialized)
struct MarkdownConfigurationTests {
    @Test("Defaults are stable and bounded")
    func defaults() {
        let value = MarkdownPreviewConfiguration.default
        #expect(value.theme == .system)
        #expect(value.codeTheme == .adaptive)
        #expect(value.sourceViewMode == .rendered)
        #expect(value.fontSize == 14)
        #expect(value.finderFontSize == 13)
        #expect(value.compactFontSize == 13)
        #expect(value.initialZoom == 1)
        #expect(value.automaticallyReloads)
        #expect(value.remembersScrollPosition)
        #expect(value.enablesMermaid && value.enablesGraphviz && value.enablesVega)
    }

    @Test("Initializer clamps unsafe numeric settings")
    func clamping() {
        let value = MarkdownPreviewConfiguration(
            fontSize: .infinity,
            finderFontSize: -4,
            lineHeight: 99,
            contentWidth: 20,
            initialZoom: .nan,
            tabWidth: 400
        )
        #expect(value.fontSize == 14)
        #expect(value.finderFontSize == 10)
        #expect(value.lineHeight == 2.2)
        #expect(value.contentWidth == 480)
        #expect(value.initialZoom == 1)
        #expect(value.tabWidth == 8)
    }

    @Test("Finder rendering uses the compact font size without changing other settings")
    func finderFontSize() {
        let value = MarkdownPreviewConfiguration(
            theme: .dark,
            fontSize: 21,
            finderFontSize: 12,
            enablesEmoji: false
        )

        let finderValue = value.usingFinderFontSize()

        #expect(finderValue.fontSize == 12)
        #expect(finderValue.finderFontSize == 12)
        #expect(finderValue.theme == .dark)
        #expect(finderValue.enablesEmoji == false)
    }

    @Test("Configuration round trips all setting families")
    func codableRoundTrip() throws {
        let original = MarkdownPreviewConfiguration(
            theme: .paper,
            codeTheme: .atomOneDark,
            fontFamily: .serif,
            sourceViewMode: .source,
            linkPolicy: .disabled,
            imagePolicy: .disabled,
            diagramMode: .disabled,
            mathMode: .disabled,
            fontSize: 18,
            finderFontSize: 15,
            lineHeight: 1.4,
            contentWidth: 1_000,
            initialZoom: 1.25,
            tabWidth: 2,
            showsTableOfContents: false,
            rendersFrontMatter: false,
            enablesTables: false,
            enablesTaskLists: false,
            enablesStrikethrough: false,
            enablesAlerts: false,
            enablesEmoji: false,
            enablesMath: false,
            enablesTypst: false,
            enablesMermaid: false,
            enablesGraphviz: false,
            enablesVega: false,
            showsLineNumbers: true,
            softBreaksAsLineBreaks: true,
            collapsesBlockquotes: true,
            automaticallyReloads: false,
            remembersScrollPosition: false
        )
        let decoded = try JSONDecoder().decode(
            MarkdownPreviewConfiguration.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    @Test("Decoding unknown and corrupt fields restores safe values")
    func tolerantDecoding() throws {
        let json = #"{"theme":"future","codeTheme":"missing","fontSize":900,"finderFontSize":-100,"initialZoom":"large","enablesEmoji":false}"#
        let decoded = try JSONDecoder().decode(
            MarkdownPreviewConfiguration.self,
            from: Data(json.utf8)
        )
        #expect(decoded.theme == .system)
        #expect(decoded.codeTheme == .adaptive)
        #expect(decoded.fontSize == 24)
        #expect(decoded.finderFontSize == 10)
        #expect(decoded.initialZoom == 1)
        #expect(!decoded.enablesEmoji)
    }

    @Test("Shared preference store saves, loads, resets, and survives corruption")
    func preferenceStore() throws {
        let suiteName = "MarkdownPreviewKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MarkdownPreferenceStore(suiteName: suiteName)
        let expected = MarkdownPreviewConfiguration(theme: .dark, codeTheme: .monokai, fontSize: 19)

        #expect(store.load() == .default)
        try store.save(expected)
        #expect(store.load() == expected)
        defaults.set(Data("not json".utf8), forKey: MarkdownPreferenceStore.defaultKey)
        #expect(store.load() == .default)
        try store.save(expected)
        store.reset()
        #expect(store.load() == .default)
    }

    @Test("File extensions and standard Markdown UTIs are recognized")
    func fileTypes() {
        for fileExtension in MarkdownPreviewFileTypes.fileExtensions {
            #expect(MarkdownPreviewFileTypes.supports(fileExtension: fileExtension))
            #expect(MarkdownPreviewFileTypes.supports(fileExtension: ".\(fileExtension.uppercased())"))
        }
        #expect(MarkdownPreviewFileTypes.supports(fileExtension: ".md"))
        #expect(!MarkdownPreviewFileTypes.supports(fileExtension: "html"))
        #expect(MarkdownPreviewFileTypes.supports(contentTypeIdentifier: "public.markdown"))
        #expect(MarkdownPreviewFileTypes.supports(contentTypeIdentifier: "net.ia.markdown"))
        #expect(!MarkdownPreviewFileTypes.supports(contentTypeIdentifier: "public.html"))
        #expect(
            MarkdownPreviewFileTypes.preparingForPreview("graph TD; A-->B", fileExtension: "mmd")
                == "```mermaid\ngraph TD; A-->B\n```"
        )
        #expect(
            MarkdownPreviewFileTypes.preparingForPreview("# Notes", fileExtension: "md")
                == "# Notes"
        )
    }
}
