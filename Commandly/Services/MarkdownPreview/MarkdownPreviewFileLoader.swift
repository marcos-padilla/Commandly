import Darwin
import Foundation
import ImageIO
import MarkdownPreviewKit

nonisolated struct MarkdownPreviewFileLimits: Equatable, Sendable {
    static let `default` = MarkdownPreviewFileLimits()

    let maximumSourceBytes: Int
    let maximumImageCount: Int
    let maximumImageBytes: Int
    let maximumTotalImageBytes: Int

    init(
        maximumSourceBytes: Int = 8 * 1_024 * 1_024,
        maximumImageCount: Int = 32,
        maximumImageBytes: Int = 2 * 1_024 * 1_024,
        maximumTotalImageBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.maximumSourceBytes = max(1, maximumSourceBytes)
        self.maximumImageCount = max(0, maximumImageCount)
        self.maximumImageBytes = max(1, maximumImageBytes)
        self.maximumTotalImageBytes = max(0, maximumTotalImageBytes)
    }
}

nonisolated enum MarkdownPreviewTextEncoding: String, Equatable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case utf32LittleEndian
    case utf32BigEndian
    case windows1252
    case isoLatin1
    case macOSRoman
}

nonisolated enum MarkdownPreviewFileError: LocalizedError, Equatable, Sendable {
    case notAFile
    case unsupportedFileType
    case sourceTooLarge(maximumBytes: Int)
    case unreadableSource
    case unsupportedEncoding
    case binaryContent

    var errorDescription: String? {
        switch self {
        case .notAFile:
            "Choose a Markdown file, not a folder."
        case .unsupportedFileType:
            "That file type is not supported by Markdown Preview."
        case .sourceTooLarge(let maximumBytes):
            "The Markdown file is larger than the \(Self.byteCount(maximumBytes)) safety limit."
        case .unreadableSource:
            "The Markdown file could not be read."
        case .unsupportedEncoding:
            "The Markdown file uses an unsupported text encoding."
        case .binaryContent:
            "The selected file appears to contain binary data instead of Markdown text."
        }
    }

    private static func byteCount(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

nonisolated enum MarkdownPreviewLoadWarning: Equatable, Hashable, Sendable {
    case unsafeImageReference
    case missingOrUnreadableImage
    case unsupportedImageType
    case imageTooLarge(maximumBytes: Int)
    case imageCountLimitReached(maximum: Int)
    case totalImageBytesLimitReached(maximumBytes: Int)
}

nonisolated struct MarkdownPreviewLoadedSource: Equatable, Sendable {
    let sourceURL: URL
    let displayName: String
    let markdown: String
    let encoding: MarkdownPreviewTextEncoding
    let sourceByteCount: Int
    let localImageDataURLs: [String: String]
    /// Omits filenames and paths so presentation and diagnostics cannot disclose private locations.
    let warnings: [MarkdownPreviewLoadWarning]
}

nonisolated protocol MarkdownPreviewFileLoading: Sendable {
    func load(from sourceURL: URL) async throws -> MarkdownPreviewLoadedSource
}

/// Reads one explicitly selected document and embeds only bounded images physically beneath it.
actor BoundedMarkdownPreviewFileLoader: MarkdownPreviewFileLoading {
    private static let maximumImageDimension = 16_384
    private static let maximumImageFrameCount = 256
    private static let maximumImagePixelCount = 64_000_000
    private static let maximumImageDecodedPixelCount = 128_000_000
    private static let maximumTotalImageDecodedPixelCount = 256_000_000

    private struct DecodedText {
        let value: String
        let encoding: MarkdownPreviewTextEncoding
    }

    private struct ImageKind {
        let mimeType: String
        let validates: @Sendable (Data) -> Bool
    }

    private enum LocalImageReadError: Error {
        case unsafePath
        case tooLarge
        case unreadable
    }

    private let limits: MarkdownPreviewFileLimits
    private let fileManager: FileManager

    init(
        limits: MarkdownPreviewFileLimits = .default,
        fileManager: FileManager = .default
    ) {
        self.limits = limits
        self.fileManager = fileManager
    }

    func load(from sourceURL: URL) async throws -> MarkdownPreviewLoadedSource {
        try Task.checkCancellation()

        let lexicalURL = sourceURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: lexicalURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false else {
            throw MarkdownPreviewFileError.notAFile
        }
        guard MarkdownPreviewFileTypes.supports(fileExtension: lexicalURL.pathExtension) else {
            throw MarkdownPreviewFileError.unsupportedFileType
        }

        let sourceData = try readBoundedFile(
            at: lexicalURL,
            maximumBytes: limits.maximumSourceBytes,
            tooLargeError: .sourceTooLarge(maximumBytes: limits.maximumSourceBytes),
            unreadableError: .unreadableSource
        )
        let decoded = try Self.decodeText(sourceData)
        guard Self.looksLikeText(decoded.value) else {
            throw MarkdownPreviewFileError.binaryContent
        }

        let canonicalURL = lexicalURL.resolvingSymlinksInPath().standardizedFileURL
        let localImageResult = try loadLocalImages(
            referencedBy: decoded.value,
            documentDirectory: canonicalURL.deletingLastPathComponent()
        )

        return MarkdownPreviewLoadedSource(
            sourceURL: canonicalURL,
            displayName: lexicalURL.lastPathComponent,
            markdown: decoded.value,
            encoding: decoded.encoding,
            sourceByteCount: sourceData.count,
            localImageDataURLs: localImageResult.dataURLs,
            warnings: localImageResult.warnings
        )
    }

    private func loadLocalImages(
        referencedBy markdown: String,
        documentDirectory: URL
    ) throws -> (dataURLs: [String: String], warnings: [MarkdownPreviewLoadWarning]) {
        let allReferences = Self.localImageReferences(in: markdown)
        let references = allReferences.prefix(limits.maximumImageCount)

        var totalBytes = 0
        var totalDecodedPixelCount = 0
        var result: [String: String] = [:]
        result.reserveCapacity(references.count)
        var warnings: [MarkdownPreviewLoadWarning] = []
        if allReferences.count > limits.maximumImageCount {
            warnings.append(.imageCountLimitReached(maximum: limits.maximumImageCount))
        }

        for reference in references {
            try Task.checkCancellation()
            guard let normalizedReference = Self.normalizedRelativeReference(reference) else {
                warnings.append(.unsafeImageReference)
                continue
            }
            guard let kind = Self.imageKind(for: normalizedReference) else {
                warnings.append(.unsupportedImageType)
                continue
            }

            let candidate = documentDirectory
                .appendingPathComponent(normalizedReference, isDirectory: false)
                .standardizedFileURL
            guard Self.contains(candidate, in: documentDirectory) else {
                warnings.append(.unsafeImageReference)
                continue
            }

            // Resolving to a different path means at least one path component was a symlink.
            guard candidate.resolvingSymlinksInPath().standardizedFileURL == candidate else {
                warnings.append(.unsafeImageReference)
                continue
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue == false else {
                warnings.append(.missingOrUnreadableImage)
                continue
            }

            let data: Data
            do {
                data = try Self.readBoundedLocalImage(
                    at: normalizedReference,
                    relativeTo: documentDirectory,
                    maximumBytes: limits.maximumImageBytes
                )
            } catch LocalImageReadError.unsafePath {
                warnings.append(.unsafeImageReference)
                continue
            } catch LocalImageReadError.tooLarge {
                warnings.append(.imageTooLarge(maximumBytes: limits.maximumImageBytes))
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warnings.append(.missingOrUnreadableImage)
                continue
            }
            guard kind.validates(data),
                  let decodedPixelCount = Self.validatedDecodedPixelCount(for: data),
                  decodedPixelCount <= Self.maximumTotalImageDecodedPixelCount - totalDecodedPixelCount else {
                warnings.append(.unsupportedImageType)
                continue
            }
            guard totalBytes <= limits.maximumTotalImageBytes - data.count else {
                warnings.append(
                    .totalImageBytesLimitReached(maximumBytes: limits.maximumTotalImageBytes)
                )
                break
            }
            totalBytes += data.count
            totalDecodedPixelCount += decodedPixelCount
            let dataURL = "data:\(kind.mimeType);base64,\(data.base64EncodedString())"
            result[normalizedReference] = dataURL
        }
        return (result, warnings)
    }

    private func readBoundedFile(
        at url: URL,
        maximumBytes: Int,
        tooLargeError: MarkdownPreviewFileError,
        unreadableError: MarkdownPreviewFileError
    ) throws -> Data {
        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw unreadableError
        }
        guard resourceValues.isRegularFile == true else { throw unreadableError }
        if let fileSize = resourceValues.fileSize, fileSize > maximumBytes {
            throw tooLargeError
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw unreadableError
        }
        defer { handle.closeFile() }

        do {
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard data.count <= maximumBytes else { throw tooLargeError }
            return data
        } catch let error as MarkdownPreviewFileError {
            throw error
        } catch {
            throw unreadableError
        }
    }

    private static func readBoundedLocalImage(
        at relativePath: String,
        relativeTo canonicalDirectory: URL,
        maximumBytes: Int
    ) throws -> Data {
        let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.isEmpty == false else {
            throw LocalImageReadError.unsafePath
        }

        var descriptor = Darwin.open(
            canonicalDirectory.path,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw LocalImageReadError.unreadable }
        defer { Darwin.close(descriptor) }

        for (index, component) in pathComponents.enumerated() {
            try Task.checkCancellation()
            let isFinalComponent = index == pathComponents.count - 1
            let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW
                | (isFinalComponent ? 0 : O_DIRECTORY)
            let nextDescriptor = component.withCString { pointer in
                Darwin.openat(descriptor, pointer, flags)
            }
            guard nextDescriptor >= 0 else {
                throw errno == ELOOP
                    ? LocalImageReadError.unsafePath
                    : LocalImageReadError.unreadable
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }

        var statusBeforeRead = stat()
        guard Darwin.fstat(descriptor, &statusBeforeRead) == 0,
              statusBeforeRead.st_mode & S_IFMT == S_IFREG,
              statusBeforeRead.st_size >= 0 else {
            throw LocalImageReadError.unreadable
        }
        guard statusBeforeRead.st_size <= maximumBytes else {
            throw LocalImageReadError.tooLarge
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data: Data
        do {
            data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        } catch {
            throw LocalImageReadError.unreadable
        }
        guard data.count <= maximumBytes else { throw LocalImageReadError.tooLarge }
        guard Int64(data.count) == statusBeforeRead.st_size else {
            throw LocalImageReadError.unreadable
        }

        var statusAfterRead = stat()
        guard Darwin.fstat(descriptor, &statusAfterRead) == 0,
              sameFileSnapshot(statusBeforeRead, statusAfterRead) else {
            throw LocalImageReadError.unreadable
        }
        return data
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

    private static func decodeText(_ data: Data) throws -> DecodedText {
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return try decode(
                Data(data.dropFirst(4)),
                as: .utf32BigEndian,
                name: .utf32BigEndian
            )
        }
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return try decode(
                Data(data.dropFirst(4)),
                as: .utf32LittleEndian,
                name: .utf32LittleEndian
            )
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return try decode(Data(data.dropFirst(3)), as: .utf8, name: .utf8)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return try decode(
                Data(data.dropFirst(2)),
                as: .utf16BigEndian,
                name: .utf16BigEndian
            )
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return try decode(
                Data(data.dropFirst(2)),
                as: .utf16LittleEndian,
                name: .utf16LittleEndian
            )
        }
        if let value = String(data: data, encoding: .utf8) {
            return DecodedText(value: value, encoding: .utf8)
        }

        if let inferred = inferredUnicodeEncoding(for: data),
           let value = String(data: data, encoding: inferred.encoding) {
            return DecodedText(value: value, encoding: inferred.name)
        }

        let fallbackEncodings: [(String.Encoding, MarkdownPreviewTextEncoding)] = [
            (.windowsCP1252, .windows1252),
            (.isoLatin1, .isoLatin1),
            (.macOSRoman, .macOSRoman),
        ]
        for candidate in fallbackEncodings {
            if let value = String(data: data, encoding: candidate.0) {
                return DecodedText(value: value, encoding: candidate.1)
            }
        }
        throw MarkdownPreviewFileError.unsupportedEncoding
    }

    private static func decode(
        _ data: Data,
        as encoding: String.Encoding,
        name: MarkdownPreviewTextEncoding
    ) throws -> DecodedText {
        guard let value = String(data: data, encoding: encoding) else {
            throw MarkdownPreviewFileError.unsupportedEncoding
        }
        return DecodedText(value: value, encoding: name)
    }

    private static func inferredUnicodeEncoding(
        for data: Data
    ) -> (encoding: String.Encoding, name: MarkdownPreviewTextEncoding)? {
        guard data.isEmpty == false else { return nil }
        let bytes = [UInt8](data.prefix(4_096))

        if bytes.count >= 4 {
            let groups = bytes.count / 4
            let leZeroTriples = (0 ..< groups).filter { index in
                let offset = index * 4
                return bytes[offset + 1] == 0 && bytes[offset + 2] == 0 && bytes[offset + 3] == 0
            }.count
            let beZeroTriples = (0 ..< groups).filter { index in
                let offset = index * 4
                return bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0
            }.count
            if leZeroTriples * 2 > groups {
                return (.utf32LittleEndian, .utf32LittleEndian)
            }
            if beZeroTriples * 2 > groups {
                return (.utf32BigEndian, .utf32BigEndian)
            }
        }

        guard bytes.count >= 2 else { return nil }
        let pairs = bytes.count / 2
        let evenZeros = stride(from: 0, to: pairs * 2, by: 2).filter { bytes[$0] == 0 }.count
        let oddZeros = stride(from: 1, to: pairs * 2, by: 2).filter { bytes[$0] == 0 }.count
        if oddZeros * 2 > pairs && evenZeros * 8 < pairs {
            return (.utf16LittleEndian, .utf16LittleEndian)
        }
        if evenZeros * 2 > pairs && oddZeros * 8 < pairs {
            return (.utf16BigEndian, .utf16BigEndian)
        }
        return nil
    }

    private static func looksLikeText(_ value: String) -> Bool {
        guard value.contains("\0") == false else { return false }
        let sample = value.unicodeScalars.prefix(4_096)
        guard sample.isEmpty == false else { return true }
        let disallowed = sample.filter { scalar in
            scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t"
        }.count
        return disallowed * 100 <= sample.count
    }

    private static func localImageReferences(in markdown: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"!\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s\)\n]+))"#
        ) else {
            return []
        }

        let fullRange = NSRange(markdown.startIndex..., in: markdown)
        var seen = Set<String>()
        var references: [String] = []
        for match in expression.matches(in: markdown, range: fullRange) {
            let capture = match.range(at: 1).location != NSNotFound
                ? match.range(at: 1)
                : match.range(at: 2)
            guard let range = Range(capture, in: markdown) else { continue }
            let reference = String(markdown[range])
            if Self.shouldLoadLocalImage(reference), seen.insert(reference).inserted {
                references.append(reference)
            }
        }
        return references
    }

    private static func shouldLoadLocalImage(_ reference: String) -> Bool {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:") == false else { return false }
        guard let scheme = URL(string: trimmed)?.scheme?.lowercased() else { return true }
        return ["http", "https"].contains(scheme) == false
    }

    private static func normalizedRelativeReference(_ reference: String) -> String? {
        let decoded = reference.removingPercentEncoding ?? reference
        var normalized = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fragment = normalized.firstIndex(of: "#") {
            normalized = String(normalized[..<fragment])
        }
        if let query = normalized.firstIndex(of: "?") {
            normalized = String(normalized[..<query])
        }
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        guard normalized.isEmpty == false,
              normalized.hasPrefix("/") == false,
              normalized.hasPrefix("~") == false,
              normalized.contains("\0") == false,
              URL(string: normalized)?.scheme == nil else {
            return nil
        }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard components.contains("..") == false else { return nil }
        let normalizedComponents = components.filter { $0.isEmpty == false && $0 != "." }
        guard normalizedComponents.isEmpty == false,
              normalizedComponents.count <= 64,
              normalized.utf8.count < Int(PATH_MAX) else {
            return nil
        }
        return normalizedComponents.joined(separator: "/")
    }

    private static func contains(_ candidate: URL, in directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.count > directoryComponents.count else { return false }
        return candidateComponents.prefix(directoryComponents.count).elementsEqual(directoryComponents)
    }

    private static func imageKind(for reference: String) -> ImageKind? {
        switch URL(fileURLWithPath: reference).pathExtension.lowercased() {
        case "png":
            return ImageKind(mimeType: "image/png") { data in
                data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            }
        case "jpg", "jpeg":
            return ImageKind(mimeType: "image/jpeg") { data in
                data.starts(with: [0xFF, 0xD8, 0xFF])
            }
        case "gif":
            return ImageKind(mimeType: "image/gif") { data in
                data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
            }
        case "webp":
            return ImageKind(mimeType: "image/webp") { data in
                data.count >= 12
                    && data.prefix(4) == Data("RIFF".utf8)
                    && data.dropFirst(8).prefix(4) == Data("WEBP".utf8)
            }
        default:
            return nil
        }
    }
}
