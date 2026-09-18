import Darwin
import Foundation
import Infrastructure

/// Injectable coordinated save operations, called synchronously only on the file writer actor.
nonisolated protocol GIFExportFileAccess: Sendable {
    func replacementDirectory(for destination: URL) throws -> URL
    func coordinate(at destination: URL, accessor: (URL) throws -> Void) throws
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws
    func removeReplacementDirectory(_ directory: URL) throws
}
nonisolated struct NativeGIFExportFileAccess: GIFExportFileAccess {
    func replacementDirectory(for destination: URL) throws -> URL { try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true) }
    func coordinate(at destination: URL, accessor: (URL) throws -> Void) throws {
        var coordinatorError: NSError?; var operationError: (any Error)?; var accessed = false
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinatorError) { url in
            accessed = true
            do { try accessor(url) } catch { operationError = error }
        }
        if let operationError { throw operationError }; if let coordinatorError { throw coordinatorError }
        guard accessed else { throw GIFSearchError.exportFailed }
    }
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws {
        if replacing { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged, backupItemName: nil, options: .usingNewMetadataOnly) }
        else { try FileManager.default.moveItem(at: staged, to: destination) }
    }
    func removeReplacementDirectory(_ directory: URL) throws { try FileManager.default.removeItem(at: directory) }
}
/// Uses an OS-provided replacement directory; never assumes a Save Panel grant authorizes siblings.
actor NativeGIFFileWriter {
    private let files: any GIFExportFileAccess
    init(files: any GIFExportFileAccess = NativeGIFExportFileAccess()) { self.files = files }
    func write(_ data: Data, to destination: URL) throws {
        try Task.checkCancellation()
        guard destination.isFileURL, !data.isEmpty, data.count <= 32 * 1_024 * 1_024 else { throw GIFSearchError.exportFailed }
        var committed = false
        do {
            let previous = try identity(destination, directory: false, permitsMissing: true)
            let replacement = try files.replacementDirectory(for: destination)
            let replacementIdentity = try identity(replacement, directory: true)
            var failure: (any Error)?
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
                let staged = replacement.appendingPathComponent(UUID().uuidString).appendingPathExtension("gif")
                try stage(data, to: staged)
                let stagedIdentity = try identity(staged, directory: false)
                try files.coordinate(at: destination) { coordinated in
                    try Task.checkCancellation()
                    guard coordinated.standardizedFileURL == destination.standardizedFileURL,
                          try identity(coordinated, directory: false, permitsMissing: true) == previous,
                          try identity(staged, directory: false) == stagedIdentity,
                          try identity(replacement, directory: true)?.sameFile(as: replacementIdentity) == true else { throw GIFSearchError.exportFailed }
                    try files.publish(staged, to: coordinated, replacing: previous != nil)
                    committed = true
                }
            } catch { failure = error }
            guard try identity(replacement, directory: true)?.sameFile(as: replacementIdentity) == true else { throw GIFSearchError.exportFailed }
            try files.removeReplacementDirectory(replacement)
            if let failure { throw failure }
        } catch is CancellationError { throw CancellationError() }
        catch { throw committed ? GIFSearchError.exportCleanupFailed : GIFSearchError.exportFailed }
    }
    private func stage(_ data: Data, to url: URL) throws {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw GIFSearchError.exportFailed }
        defer { Darwin.close(descriptor) }
        guard fchmod(descriptor, 0o600) == 0 else { throw GIFSearchError.exportFailed }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw GIFSearchError.exportFailed }
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = Darwin.write(descriptor, base.advanced(by: offset), min(64 * 1_024, bytes.count - offset))
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw GIFSearchError.exportFailed }; offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw GIFSearchError.exportFailed }
        try Task.checkCancellation()
    }
    private struct Identity: Equatable {
        let device: UInt64; let inode: UInt64; let bytes: Int64; let modified: Int64; let nanos: Int64; let changed: Int64; let changeNanos: Int64
        func sameFile(as other: Self?) -> Bool { device == other?.device && inode == other?.inode }
    }
    private func identity(_ url: URL, directory: Bool, permitsMissing: Bool = false) throws -> Identity? {
        var value = stat()
        if lstat(url.path, &value) != 0 {
            if permitsMissing, errno == ENOENT { return nil }; throw GIFSearchError.exportFailed
        }
        guard value.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { throw GIFSearchError.exportFailed }
        return .init(device: UInt64(value.st_dev), inode: UInt64(value.st_ino), bytes: value.st_size, modified: Int64(value.st_mtimespec.tv_sec),
                     nanos: Int64(value.st_mtimespec.tv_nsec), changed: Int64(value.st_ctimespec.tv_sec), changeNanos: Int64(value.st_ctimespec.tv_nsec))
    }
}
