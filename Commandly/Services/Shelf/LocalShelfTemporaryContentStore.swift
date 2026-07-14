import AppCore
import Foundation
import Infrastructure
import OSLog
import UniformTypeIdentifiers

/// Actor-confined private files that let clipboard text and images use Shelf's URL pipeline.
///
/// Each board owns one store. It writes only beneath Commandly's temporary container, never logs
/// payloads or paths, and removes the entire private directory when that board is torn down.
actor LocalShelfTemporaryContentStore: ShelfTemporaryContentStoring {
    private let fileManager: FileManager
    private let rootURL: URL
    private let logger: Logger
    private var hasCreatedRoot = false

    init(
        fileManager: FileManager = FileManager(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        identifier: UUID = UUID(),
        logger: Logger = Logger(
            subsystem: "com.businessmate360.Commandly",
            category: "ShelfTemporaryContent"
        )
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.rootURL = temporaryDirectory
            .appendingPathComponent("Commandly", isDirectory: true)
            .appendingPathComponent("Shelf-\(identifier.uuidString)", isDirectory: true)
    }

    func createTextFile(containing text: String) throws -> URL {
        guard let data = text.data(using: .utf8) else {
            throw CommandlyError.invalidInput("That clipboard text could not be represented as UTF-8.")
        }
        return try write(data, baseName: "Clipboard Text", pathExtension: "txt")
    }

    func createImageFile(_ image: PasteboardImageContent) throws -> URL {
        guard let type = UTType(image.typeIdentifier), type.conforms(to: .image),
              let preferredExtension = type.preferredFilenameExtension else {
            throw CommandlyError.unsupported("That clipboard image format is unsupported.")
        }
        return try write(
            image.data,
            baseName: "Clipboard Image",
            pathExtension: preferredExtension
        )
    }

    func discard(_ urls: [URL]) {
        for url in urls where owns(url) {
            do {
                try fileManager.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                continue
            } catch {
                logger.error("Could not remove private temporary Shelf content")
            }
        }
        removeRootIfEmpty()
    }

    func discardAll() {
        guard hasCreatedRoot else { return }
        do {
            try fileManager.removeItem(at: rootURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // The owned root was already removed by an earlier item-level cleanup.
        } catch {
            logger.error("Could not remove the private temporary Shelf directory")
        }
        hasCreatedRoot = false
    }

    private func write(_ data: Data, baseName: String, pathExtension: String) throws -> URL {
        try Task.checkCancellation()
        do {
            try createRootIfNeeded()
            let destination = uniqueURL(baseName: baseName, pathExtension: pathExtension)
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommandlyError {
            throw error
        } catch {
            throw CommandlyError.internalFailure("Couldn’t create temporary Shelf content.")
        }
    }

    private func createRootIfNeeded() throws {
        guard hasCreatedRoot == false else { return }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        hasCreatedRoot = true
    }

    private func uniqueURL(baseName: String, pathExtension: String) -> URL {
        var sequence = 1
        var candidate = rootURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(pathExtension)
        while fileManager.fileExists(atPath: candidate.path) {
            sequence += 1
            candidate = rootURL
                .appendingPathComponent("\(baseName) \(sequence)")
                .appendingPathExtension(pathExtension)
        }
        return candidate
    }

    private func owns(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private func removeRootIfEmpty() {
        guard hasCreatedRoot else { return }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil
            )
            guard contents.isEmpty else { return }
            try fileManager.removeItem(at: rootURL)
            hasCreatedRoot = false
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            hasCreatedRoot = false
        } catch {
            logger.error("Could not inspect or remove the private temporary Shelf directory")
        }
    }
}
