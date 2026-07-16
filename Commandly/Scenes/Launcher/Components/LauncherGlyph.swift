import DesignSystem
import Foundation
import SearchKit
import SwiftUI

/// Semantic families retained by artwork classification without decorating launcher rows.
enum LauncherGlyphTone: Sendable {
    case blue
    case cyan
    case indigo
    case mint
    case amber
    case coral
    case slate
}

/// A quiet monochrome treatment for command, file, and clipboard glyphs.
struct LauncherGlyph: View {
    let systemName: String
    let tone: LauncherGlyphTone
    var isSelected = false
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemName)
            .symbolVariant(.fill)
            .symbolRenderingMode(.monochrome)
            .commandlyFont(size: size * 0.47, weight: .semibold)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Deterministic artwork selection for local files. The actual asset remains an SF
/// Symbol so it is crisp at compact launcher sizes and follows macOS accessibility.
enum LauncherFileArtwork: Equatable, Sendable {
    case folder
    case image
    case audio
    case video
    case archive
    case sourceCode
    case spreadsheet
    case presentation
    case pdf
    case text
    case web
    case font
    case generic

    init(item: FileSearchItem) {
        if item.kind == .folder {
            self = .folder
            return
        }
        self = Self.classify(
            contentTypeIdentifier: item.contentTypeIdentifier,
            pathExtension: item.url.pathExtension
        )
    }

    init(fileURL: URL) {
        self = Self.classify(contentTypeIdentifier: nil, pathExtension: fileURL.pathExtension)
    }

    var symbolName: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo.fill"
        case .audio: return "speaker.wave.2.fill"
        case .video: return "film.fill"
        case .archive: return "archivebox.fill"
        case .sourceCode: return "chevron.left.forwardslash.chevron.right"
        case .spreadsheet: return "tablecells.fill"
        case .presentation: return "rectangle.fill.on.rectangle.fill"
        case .pdf: return "doc.richtext.fill"
        case .text: return "doc.text.fill"
        case .web: return "globe.americas.fill"
        case .font: return "textformat"
        case .generic: return "doc.fill"
        }
    }

    var tone: LauncherGlyphTone {
        switch self {
        case .folder, .web: return .cyan
        case .image, .video: return .indigo
        case .audio: return .mint
        case .archive, .presentation: return .amber
        case .sourceCode: return .slate
        case .spreadsheet: return .mint
        case .pdf: return .coral
        case .text, .font, .generic: return .blue
        }
    }

    private static func classify(contentTypeIdentifier: String?, pathExtension: String) -> Self {
        let identifier = contentTypeIdentifier?.lowercased() ?? ""
        let ext = pathExtension.lowercased()

        if identifier.contains("image") || imageExtensions.contains(ext) { return .image }
        if identifier.contains("audio") || audioExtensions.contains(ext) { return .audio }
        if identifier.contains("movie") || identifier.contains("video") || videoExtensions.contains(ext) { return .video }
        if identifier.contains("archive") || identifier.contains("zip") || archiveExtensions.contains(ext) { return .archive }
        if identifier.contains("source") || identifier.contains("script") || sourceExtensions.contains(ext) { return .sourceCode }
        if spreadsheetExtensions.contains(ext) { return .spreadsheet }
        if presentationExtensions.contains(ext) { return .presentation }
        if identifier.contains("pdf") || ext == "pdf" { return .pdf }
        if identifier.contains("font") || fontExtensions.contains(ext) { return .font }
        if webExtensions.contains(ext) { return .web }
        if identifier.contains("text") || textExtensions.contains(ext) { return .text }
        return .generic
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "svg"]
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
    private static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "bz2", "xz", "7z", "rar"]
    private static let sourceExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "js", "ts", "tsx", "jsx", "py", "rb", "rs", "go", "java", "kt", "sh", "zsh"]
    private static let spreadsheetExtensions: Set<String> = ["csv", "tsv", "xls", "xlsx", "numbers"]
    private static let presentationExtensions: Set<String> = ["ppt", "pptx", "key"]
    private static let fontExtensions: Set<String> = ["otf", "ttf", "ttc", "woff", "woff2"]
    private static let webExtensions: Set<String> = ["html", "htm", "webloc", "url"]
    private static let textExtensions: Set<String> = ["txt", "md", "rtf", "doc", "docx", "pages", "json", "yaml", "yml", "xml"]
}

enum LauncherCommandArtwork {
    static func filledSymbol(for symbolName: String) -> String {
        switch symbolName {
        case "clipboard": return "clipboard.fill"
        case "gearshape": return "gearshape.fill"
        case "calendar": return "calendar"
        case "link": return "link"
        case "power": return "power.circle.fill"
        case "sparkles": return "sparkles"
        case "rectangle.split.2x1": return "rectangle.split.2x1.fill"
        case "doc.text.magnifyingglass": return "doc.text.magnifyingglass"
        default: return symbolName
        }
    }

    static func tone(for symbolName: String) -> LauncherGlyphTone {
        switch symbolName {
        case "clipboard", "clipboard.fill": return .coral
        case "doc.text.magnifyingglass", "magnifyingglass": return .cyan
        case "gearshape", "gearshape.fill": return .slate
        case "calendar": return .indigo
        case "link": return .mint
        case "power", "power.circle.fill": return .coral
        default: return .blue
        }
    }
}
