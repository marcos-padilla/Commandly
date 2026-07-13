import AppCore
import Foundation
import Infrastructure
import UniformTypeIdentifiers

/// Reads file and folder metadata on an actor isolated from UI state.
///
/// This adapter never reads file contents and never logs URLs, filenames, or resource values.
actor WorkspaceFileResourceMetadataReader: FileResourceMetadataReading {
    private let fileManager: FileManager

    init(fileManager: FileManager = FileManager()) {
        self.fileManager = fileManager
    }

    func metadata(for urls: [URL]) async throws -> [FileResourceMetadata] {
        do {
            var result: [FileResourceMetadata] = []
            result.reserveCapacity(urls.count)

            for suppliedURL in urls {
                try Task.checkCancellation()
                guard suppliedURL.isFileURL else {
                    throw CommandlyError.invalidInput("Shelf items must be file URLs.")
                }

                let url = suppliedURL.standardizedFileURL
                var isDirectoryValue: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectoryValue) else {
                    throw CommandlyError.notFound("Shelf item")
                }

                let values = try url.resourceValues(forKeys: Self.resourceKeys)
                let isDirectory = values.isDirectory ?? isDirectoryValue.boolValue
                result.append(
                    FileResourceMetadata(
                        url: url,
                        displayName: values.localizedName ?? url.lastPathComponent,
                        isDirectory: isDirectory,
                        byteCount: isDirectory ? nil : values.fileSize.map(Int64.init),
                        contentTypeIdentifier: values.contentType?.identifier,
                        creationDate: values.creationDate,
                        modificationDate: values.contentModificationDate
                    )
                )
            }

            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommandlyError {
            throw error
        } catch {
            throw CommandlyError.internalFailure("Couldn’t read Shelf item metadata.")
        }
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .localizedNameKey,
        .isDirectoryKey,
        .fileSizeKey,
        .contentTypeKey,
        .creationDateKey,
        .contentModificationDateKey
    ]
}
