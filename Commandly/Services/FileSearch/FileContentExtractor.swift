import CoreServices
import Foundation
import PDFKit
import SearchKit
import UniformTypeIdentifiers
import Vision

struct FileContentExtraction: Sendable {
    let text: String
    let metadata: String
    let tags: [String]
}

/// Bounded, on-device content and metadata extraction for the background indexer.
enum FileContentExtractor {
    nonisolated static let maximumTextBytes: Int64 = 1_024 * 1_024
    nonisolated static let maximumCharacters = 64_000
    nonisolated static let maximumPDFPages = 40
    nonisolated static let maximumImageBytes: Int64 = 20 * 1_024 * 1_024

    nonisolated static func extract(_ candidate: FileContentCandidate) async -> FileContentExtraction {
        if Task.isCancelled {
            return FileContentExtraction(text: "", metadata: candidate.metadataText, tags: candidate.tags)
        }
        let url = URL(fileURLWithPath: candidate.path)
        let spotlight = spotlightMetadata(for: url)
        var metadataParts = [candidate.metadataText]
        metadataParts.append(contentsOf: spotlight.metadata)
        let tags = Array(Set(candidate.tags + spotlight.tags)).sorted()

        if let spotlightText = spotlight.text, spotlightText.isEmpty == false {
            return FileContentExtraction(
                text: clipped(spotlightText),
                metadata: clipped(metadataParts.joined(separator: "\n")),
                tags: tags
            )
        }

        let type = candidate.contentTypeIdentifier.flatMap(UTType.init)
        let extractedText: String
        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            extractedText = extractPDF(url)
        } else if type?.conforms(to: .image) == true,
                  (candidate.byteCount ?? 0) <= maximumImageBytes {
            extractedText = await extractImageText(url)
        } else if isReadableText(type: type, extension: url.pathExtension),
                  (candidate.byteCount ?? 0) <= maximumTextBytes {
            extractedText = extractTextFile(url)
        } else {
            extractedText = ""
        }
        return FileContentExtraction(
            text: clipped(extractedText),
            metadata: clipped(metadataParts.joined(separator: "\n")),
            tags: tags
        )
    }

    private nonisolated static func spotlightMetadata(
        for url: URL
    ) -> (text: String?, metadata: [String], tags: [String]) {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString) else {
            return (nil, [], [])
        }
        let text = MDItemCopyAttribute(item, kMDItemTextContent) as? String
        let stringKeys: [CFString] = [
            kMDItemTitle,
            kMDItemDescription,
            kMDItemFinderComment,
            kMDItemKeywords,
            kMDItemAuthors,
            kMDItemOrganizations,
            kMDItemWhereFroms
        ]
        var metadata: [String] = []
        for key in stringKeys {
            let value = MDItemCopyAttribute(item, key)
            if let string = value as? String, string.isEmpty == false {
                metadata.append(string)
            } else if let strings = value as? [String] {
                metadata.append(contentsOf: strings)
            }
        }
        let tags = MDItemCopyAttribute(item, "kMDItemUserTags" as CFString) as? [String] ?? []
        return (text, metadata, tags)
    }

    private nonisolated static func extractPDF(_ url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var text = ""
        for index in 0..<min(document.pageCount, maximumPDFPages) {
            guard Task.isCancelled == false else { break }
            guard let pageText = document.page(at: index)?.string else { continue }
            append(pageText, to: &text)
            if text.count >= maximumCharacters { break }
        }
        return text
    }

    private nonisolated static func extractTextFile(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Int(maximumTextBytes)), data.isEmpty == false else {
            return ""
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private nonisolated static func extractImageText(_ url: URL) async -> String {
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let observations = try await request.perform(on: url)
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    private nonisolated static func isReadableText(type: UTType?, extension extensionName: String) -> Bool {
        if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
            return true
        }
        return Set([
            "csv", "tsv", "json", "xml", "yaml", "yml", "toml", "md", "markdown",
            "txt", "rtf", "log", "ini", "conf", "swift", "m", "mm", "h", "c", "cpp",
            "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java", "kt", "sh", "zsh"
        ]).contains(extensionName.lowercased())
    }

    private nonisolated static func append(_ value: String, to destination: inout String) {
        let remaining = maximumCharacters - destination.count
        guard remaining > 0 else { return }
        if destination.isEmpty == false { destination.append("\n") }
        destination.append(contentsOf: value.prefix(remaining))
    }

    private nonisolated static func clipped(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= maximumCharacters ? trimmed : String(trimmed.prefix(maximumCharacters))
    }
}
