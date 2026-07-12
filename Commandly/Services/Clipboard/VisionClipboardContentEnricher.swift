import AppKit
import Foundation
import PDFKit
import Vision

/// On-device Vision / PDFKit / text-file enricher for clipboard history.
///
/// Caps keep indexing bounded. Never logs extracted content.
struct VisionClipboardContentEnricher: ClipboardContentEnriching {
    static let maxImageDimension: CGFloat = 1_600
    static let maxOCRCharacters = 8_000
    static let maxPDFPages = 20
    static let maxTextFileBytes = 512 * 1_024
    static let minImageDimension: CGFloat = 16
    static let classificationConfidenceThreshold: Float = 0.2
    static let maxClassificationLabels = 12

    func enrich(_ entry: ClipboardHistoryEntry) async -> ClipboardEnrichment {
        if Task.isCancelled {
            return .skipped()
        }

        switch entry.contentType {
        case .text:
            return ClipboardEnrichment(
                searchableText: nil,
                classificationLabels: [],
                status: .notNeeded
            )
        case .image:
            guard let data = entry.imageTIFFData else { return .skipped() }
            return await enrichImage(data: data)
        case .fileURL:
            return await enrichFileURLs(entry.fileURLs)
        }
    }

    // MARK: - Images

    private func enrichImage(data: Data) async -> ClipboardEnrichment {
        guard let cgImage = Self.makeDownscaledCGImage(from: data) else {
            return .failed()
        }
        return await analyze(cgImage: cgImage)
    }

    private func enrichImage(fileURL: URL) async -> ClipboardEnrichment {
        guard let cgImage = Self.makeDownscaledCGImage(fromFileURL: fileURL) else {
            return .failed()
        }
        return await analyze(cgImage: cgImage)
    }

    private func analyze(cgImage: CGImage) async -> ClipboardEnrichment {
        if Task.isCancelled { return .skipped() }

        async let ocrText = recognizeText(in: cgImage)
        async let labels = classify(cgImage)
        let text = await ocrText
        let classificationLabels = await labels

        if Task.isCancelled { return .skipped() }
        return .ready(searchableText: text, labels: classificationLabels)
    }

    private func recognizeText(in cgImage: CGImage) async -> String? {
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let observations = try await request.perform(on: cgImage)
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            guard lines.isEmpty == false else { return nil }
            let joined = lines.joined(separator: "\n")
            if joined.count <= Self.maxOCRCharacters {
                return joined
            }
            return String(joined.prefix(Self.maxOCRCharacters))
        } catch {
            return nil
        }
    }

    private func classify(_ cgImage: CGImage) async -> [String] {
        do {
            let request = ClassifyImageRequest()
            let observations = try await request.perform(on: cgImage)
            let filtered = observations
                .filter { $0.confidence >= Self.classificationConfidenceThreshold }
                .sorted { $0.confidence > $1.confidence }
                .prefix(Self.maxClassificationLabels)
            return filtered.map(\.identifier)
        } catch {
            return []
        }
    }

    // MARK: - Files

    private func enrichFileURLs(_ urls: [URL]) async -> ClipboardEnrichment {
        guard urls.isEmpty == false else { return .skipped() }

        var textChunks: [String] = []
        var labels: [String] = []
        var sawSupported = false
        var sawFailure = false

        for url in urls {
            if Task.isCancelled { return .skipped() }

            let ext = url.pathExtension.lowercased()
            if ClipboardImageFile.isImageFileURL(url) {
                sawSupported = true
                let result = await enrichImage(fileURL: url)
                switch result.status {
                case .ready:
                    if let text = result.searchableText {
                        textChunks.append(text)
                    }
                    labels.append(contentsOf: result.classificationLabels)
                case .failed:
                    sawFailure = true
                case .skipped, .pending, .notNeeded:
                    break
                }
                continue
            }

            if ext == "pdf" {
                sawSupported = true
                if let text = extractPDFText(from: url) {
                    textChunks.append(text)
                } else {
                    sawFailure = true
                }
                continue
            }

            if Self.isRTFExtension(ext) {
                sawSupported = true
                if let text = extractRTFText(from: url) {
                    textChunks.append(text)
                } else {
                    sawFailure = true
                }
                continue
            }

            if Self.isPlainTextExtension(ext) {
                sawSupported = true
                if let text = extractPlainText(from: url) {
                    textChunks.append(text)
                } else {
                    sawFailure = true
                }
                continue
            }
        }

        if sawSupported == false {
            return .skipped()
        }

        let searchable = textChunks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped: String? = {
            guard searchable.isEmpty == false else { return nil }
            if searchable.count <= Self.maxOCRCharacters {
                return searchable
            }
            return String(searchable.prefix(Self.maxOCRCharacters))
        }()

        if clipped == nil && labels.isEmpty && sawFailure {
            return .failed()
        }
        return .ready(searchableText: clipped, labels: labels)
    }

    private func extractPDFText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageCount = min(document.pageCount, Self.maxPDFPages)
        guard pageCount > 0 else { return nil }

        var chunks: [String] = []
        var total = 0
        for index in 0 ..< pageCount {
            if Task.isCancelled { break }
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            if total + trimmed.count > Self.maxOCRCharacters {
                let remaining = Self.maxOCRCharacters - total
                if remaining > 0 {
                    chunks.append(String(trimmed.prefix(remaining)))
                }
                break
            }
            chunks.append(trimmed)
            total += trimmed.count
        }
        let joined = chunks.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private func extractPlainText(from url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0,
              size <= Self.maxTextFileBytes
        else {
            // Still try a bounded read if size is unknown.
            return readBoundedUTF8(from: url)
        }
        return readBoundedUTF8(from: url)
    }

    private func readBoundedUTF8(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxTextFileBytes),
              data.isEmpty == false
        else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count <= Self.maxOCRCharacters {
            return trimmed
        }
        return String(trimmed.prefix(Self.maxOCRCharacters))
    }

    private func extractRTFText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= Self.maxTextFileBytes,
              data.isEmpty == false
        else {
            return nil
        }
        guard let attributed = NSAttributedString(
            rtf: data,
            documentAttributes: nil
        ) else {
            return nil
        }
        let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count <= Self.maxOCRCharacters {
            return trimmed
        }
        return String(trimmed.prefix(Self.maxOCRCharacters))
    }

    // MARK: - Image helpers

    private static func makeDownscaledCGImage(from data: Data) -> CGImage? {
        guard let image = NSImage(data: data) else { return nil }
        return downscaledCGImage(from: image)
    }

    private static func makeDownscaledCGImage(fromFileURL url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return downscaledCGImage(from: image)
    }

    private static func downscaledCGImage(from image: NSImage) -> CGImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        guard width >= minImageDimension, height >= minImageDimension else {
            return nil
        }

        let longest = max(width, height)
        if longest <= maxImageDimension {
            return source
        }

        let scale = maxImageDimension / longest
        let targetSize = NSSize(width: floor(width * scale), height: floor(height * scale))
        guard targetSize.width >= minImageDimension, targetSize.height >= minImageDimension else {
            return nil
        }

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func isPlainTextExtension(_ ext: String) -> Bool {
        let allowed: Set<String> = [
            "txt", "md", "markdown", "csv", "tsv", "json", "jsonl",
            "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp",
            "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs",
            "java", "kt", "kts", "yml", "yaml", "toml", "xml",
            "html", "htm", "css", "scss", "sh", "zsh", "bash",
            "log", "ini", "conf", "cfg", "env", "sql"
        ]
        return allowed.contains(ext)
    }

    private static func isRTFExtension(_ ext: String) -> Bool {
        ext == "rtf" || ext == "rtfd"
    }
}
