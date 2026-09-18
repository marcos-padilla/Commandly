import Darwin
import Foundation
import ImageIO
import MarkdownPreviewKit

actor MarkdownQuickLookPreviewBuilder {
    private static let maximumSourceByteCount = 500 * 1_024
    private static let maximumImageCount = 32
    private static let maximumImageByteCount = 2 * 1_024 * 1_024
    private static let maximumTotalImageByteCount = 8 * 1_024 * 1_024
    private static let maximumImageDimension = 16_384
    private static let maximumImageFrameCount = 256
    private static let maximumImagePixelCount = 64_000_000
    private static let maximumImageDecodedPixelCount = 128_000_000
    private static let maximumTotalImageDecodedPixelCount = 256_000_000

    func renderFile(at url: URL) throws -> String {
        try Task.checkCancellation()

        let boundedData = try Self.readBoundedSource(at: url)
        let isTruncated = boundedData.count > Self.maximumSourceByteCount
        let renderData = isTruncated ? boundedData.prefix(Self.maximumSourceByteCount) : boundedData[...]
        var markdown = try Self.decode(renderData, isTruncated: isTruncated)

        guard Self.looksLikeText(markdown) else {
            throw MarkdownQuickLookError.binaryContent
        }

        if isTruncated {
            if let lastNewline = markdown.lastIndex(of: "\n") {
                markdown = String(markdown[...lastNewline])
            } else {
                markdown = ""
            }
        }

        let localImages = try Self.localImageDataURLs(in: markdown, documentURL: url)
        var sourceMarkdown = markdown
        var renderMarkdown = MarkdownPreviewFileTypes.preparingForPreview(
            markdown,
            fileExtension: url.pathExtension
        )
        if isTruncated {
            let truncationNotice = "\n\n---\n\n_Preview limited to the first 500 KiB._"
            sourceMarkdown += truncationNotice
            renderMarkdown += truncationNotice
        }

        try Task.checkCancellation()
        let configuration = MarkdownPreferenceStore().load().usingFinderFontSize()
        return MarkdownRenderer().render(
            MarkdownRenderInput(
                markdown: renderMarkdown,
                sourceMarkdown: sourceMarkdown,
                documentTitle: url.lastPathComponent,
                localImageDataURLs: localImages
            ),
            configuration: configuration
        ).html
    }

    private static func readBoundedSource(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        return try handle.read(upToCount: maximumSourceByteCount + 1) ?? Data()
    }

    private static func decode(_ data: Data.SubSequence, isTruncated: Bool) throws -> String {
        let completeData = Data(data)

        if completeData.starts(with: [0xFF, 0xFE]) {
            let candidate = isTruncated && completeData.count.isMultiple(of: 2) == false
                ? completeData.dropLast()
                : completeData[...]
            guard let markdown = String(data: Data(candidate), encoding: .utf16LittleEndian) else {
                throw MarkdownQuickLookError.unsupportedTextEncoding
            }
            return markdown.removingByteOrderMark()
        }
        if completeData.starts(with: [0xFE, 0xFF]) {
            let candidate = isTruncated && completeData.count.isMultiple(of: 2) == false
                ? completeData.dropLast()
                : completeData[...]
            guard let markdown = String(data: Data(candidate), encoding: .utf16BigEndian) else {
                throw MarkdownQuickLookError.unsupportedTextEncoding
            }
            return markdown.removingByteOrderMark()
        }
        if let markdown = String(data: completeData, encoding: .utf8) {
            return markdown.removingByteOrderMark()
        }
        if isTruncated {
            for byteCountToDrop in 1 ... 3 where completeData.count > byteCountToDrop {
                let candidate = completeData.dropLast(byteCountToDrop)
                if let markdown = String(data: Data(candidate), encoding: .utf8) {
                    return markdown.removingByteOrderMark()
                }
            }
        }
        throw MarkdownQuickLookError.unsupportedTextEncoding
    }

    private static func looksLikeText(_ value: String) -> Bool {
        guard value.contains("\0") == false else { return false }
        let sample = value.unicodeScalars.prefix(4_096)
        guard sample.isEmpty == false else { return true }
        let disallowedControlCount = sample.filter { scalar in
            scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t"
        }.count
        return disallowedControlCount * 100 <= sample.count
    }

    private static func localImageDataURLs(
        in markdown: String,
        documentURL: URL
    ) throws -> [String: String] {
        let expression = try NSRegularExpression(
            pattern: #"!\[[^\]\r\n]*\]\(\s*(?:<([^>\r\n]+)>|([^\s\)\r\n]+))(?:\s+(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|\([^\)\r\n]*\)))?\s*\)"#
        )
        let entireDocument = NSRange(markdown.startIndex..., in: markdown)
        var references: [LocalImageReference] = []
        var seenMappingKeys: Set<String> = []

        expression.enumerateMatches(in: markdown, range: entireDocument) { match, _, stop in
            guard references.count < maximumImageCount else {
                stop.pointee = true
                return
            }
            guard let match else { return }

            let angleBracketRange = match.range(at: 1)
            let usesAngleBrackets = angleBracketRange.location != NSNotFound
            let referenceRange = usesAngleBrackets
                ? angleBracketRange
                : match.range(at: 2)
            guard let swiftRange = Range(referenceRange, in: markdown) else { return }

            let rawReference = String(markdown[swiftRange])
            let mappingKey = usesAngleBrackets ? "<\(rawReference)>" : rawReference
            guard let normalizedFilePath = normalizedRelativeImageReference(rawReference),
                  seenMappingKeys.insert(mappingKey).inserted else {
                return
            }
            references.append(
                LocalImageReference(mappingKey: mappingKey, normalizedFilePath: normalizedFilePath)
            )
        }

        let canonicalDirectory = documentURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var dataURLs: [String: String] = [:]
        var totalImageByteCount = 0
        var totalImageDecodedPixelCount = 0

        for reference in references {
            try Task.checkCancellation()
            guard let image = validatedImage(
                at: reference.normalizedFilePath,
                relativeTo: canonicalDirectory
            ),
            image.data.count <= maximumTotalImageByteCount - totalImageByteCount,
            image.decodedPixelCount <= maximumTotalImageDecodedPixelCount - totalImageDecodedPixelCount else {
                continue
            }

            totalImageByteCount += image.data.count
            totalImageDecodedPixelCount += image.decodedPixelCount
            dataURLs[reference.mappingKey] = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
        }

        return dataURLs
    }

    private static func normalizedRelativeImageReference(_ rawReference: String) -> String? {
        var reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
        var decodingPassCount = 0

        while true {
            guard let decoded = reference.removingPercentEncoding else { return nil }
            guard decoded != reference else { break }
            decodingPassCount += 1
            guard decodingPassCount <= 4 else { return nil }
            reference = decoded
        }

        reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        while reference.hasPrefix("./") {
            reference.removeFirst(2)
        }

        guard !reference.isEmpty,
              !reference.hasPrefix("/"),
              !reference.hasPrefix("~"),
              !reference.contains("\\"),
              !reference.contains("\0"),
              URLComponents(string: reference)?.scheme == nil else {
            return nil
        }

        let components = reference.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else { return nil }

        let normalizedComponents = components.filter { !$0.isEmpty && $0 != "." }
        guard !normalizedComponents.isEmpty,
              normalizedComponents.count <= 64,
              reference.utf8.count < Int(PATH_MAX) else {
            return nil
        }
        return normalizedComponents.joined(separator: "/")
    }

    private static func validatedImage(
        at relativePath: String,
        relativeTo canonicalDirectory: URL
    ) -> ValidatedImage? {
        let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.isEmpty == false else { return nil }

        var descriptor = Darwin.open(
            canonicalDirectory.path,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        do {
            for (index, component) in pathComponents.enumerated() {
                let isFinalComponent = index == pathComponents.count - 1
                let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW
                    | (isFinalComponent ? 0 : O_DIRECTORY)
                let nextDescriptor = component.withCString { pointer in
                    Darwin.openat(descriptor, pointer, flags)
                }
                guard nextDescriptor >= 0 else { return nil }
                Darwin.close(descriptor)
                descriptor = nextDescriptor
            }

            var statusBeforeRead = stat()
            guard Darwin.fstat(descriptor, &statusBeforeRead) == 0,
                  statusBeforeRead.st_mode & S_IFMT == S_IFREG,
                  statusBeforeRead.st_size >= 0,
                  statusBeforeRead.st_size <= maximumImageByteCount else {
                return nil
            }

            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            let data = try handle.read(upToCount: maximumImageByteCount + 1) ?? Data()
            guard data.count <= maximumImageByteCount,
                  Int64(data.count) == statusBeforeRead.st_size else {
                return nil
            }

            var statusAfterRead = stat()
            guard Darwin.fstat(descriptor, &statusAfterRead) == 0,
                  sameFileSnapshot(statusBeforeRead, statusAfterRead),
                  let mimeType = imageMIMEType(for: data),
                  let decodedPixelCount = validatedDecodedPixelCount(for: data) else {
                return nil
            }
            return ValidatedImage(
                data: data,
                mimeType: mimeType,
                decodedPixelCount: decodedPixelCount
            )
        } catch {
            // Missing, inaccessible, or concurrently changed images leave their alt text intact.
            return nil
        }
    }

    private static func sameFileSnapshot(_ first: stat, _ second: stat) -> Bool {
        first.st_dev == second.st_dev
            && first.st_ino == second.st_ino
            && first.st_mode == second.st_mode
            && first.st_size == second.st_size
            && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
            && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
            && first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec
            && first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
    }

    private static func validatedDecodedPixelCount(for data: Data) -> Int? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0, frameCount <= maximumImageFrameCount else { return nil }

        var totalPixelCount = 0
        for frameIndex in 0 ..< frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                frameIndex,
                options
            ) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0,
            width <= maximumImageDimension,
            height <= maximumImageDimension,
            width <= maximumImagePixelCount / height else {
                return nil
            }

            let pixelCount = width * height
            guard pixelCount <= maximumImageDecodedPixelCount - totalPixelCount else {
                return nil
            }
            totalPixelCount += pixelCount
        }
        return totalPixelCount
    }

    private static func imageMIMEType(for data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) {
            return "image/gif"
        }
        if data.count >= 12,
           data.prefix(4) == Data("RIFF".utf8),
           data.dropFirst(8).prefix(4) == Data("WEBP".utf8) {
            return "image/webp"
        }
        return nil
    }
}

private struct ValidatedImage {
    let data: Data
    let mimeType: String
    let decodedPixelCount: Int
}

private struct LocalImageReference {
    let mappingKey: String
    let normalizedFilePath: String
}

enum MarkdownQuickLookError: LocalizedError {
    case binaryContent
    case previewViewUnavailable
    case unsupportedTextEncoding
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .binaryContent:
            "The selected file appears to contain binary data instead of Markdown text."
        case .previewViewUnavailable:
            "Markdown Preview could not create its preview view."
        case .unsupportedTextEncoding:
            "Markdown Preview supports UTF-8 and byte-order-marked UTF-16 files."
        case .unsupportedURL:
            "Markdown Preview can only open local files."
        }
    }
}

private extension String {
    nonisolated func removingByteOrderMark() -> String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }
}
