import Darwin
import Foundation
import Infrastructure

/// Filesystem values only; no source URL or video content is retained in the review identity.
nonisolated struct ScreenRecordingFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let bytes: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    static func read(at url: URL) throws -> Self {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ScreenRecordingError.invalidArtifact }
        defer { Darwin.close(descriptor) }
        return try read(descriptor: descriptor)
    }

    static func read(descriptor: Int32) throws -> Self {
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFREG else {
            throw ScreenRecordingError.invalidArtifact
        }
        return Self(device: UInt64(value.st_dev), inode: UInt64(value.st_ino), bytes: value.st_size,
                    modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                    changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanoseconds: Int64(value.st_ctimespec.tv_nsec))
    }
}

/// Injectable synchronous native save operations. The accessor must finish before coordination returns.
nonisolated protocol ScreenRecordingExportFileAccess: Sendable {
    func replacementDirectory(for destination: URL) throws -> URL
    func coordinateWrite(at destination: URL, accessor: (URL) throws -> Void) throws
    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws
    func removeReplacementDirectory(_ directory: URL) throws
}

nonisolated struct NativeScreenRecordingExportFileAccess: ScreenRecordingExportFileAccess {
    func replacementDirectory(for destination: URL) throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: destination, create: true)
    }

    func coordinateWrite(at destination: URL, accessor: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: (any Error)?
        var accessed = false
        coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            accessed = true
            do { try accessor(coordinatedURL) }
            catch { operationError = error }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
        guard accessed else { throw ScreenRecordingError.exportFailed }
    }

    func publish(_ staged: URL, to destination: URL, replacing: Bool) throws {
        if replacing {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged,
                                                     backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            // The replacement directory is on the destination volume. moveItem refuses an
            // existing destination, including one that appeared after our coordinated check.
            try FileManager.default.moveItem(at: staged, to: destination)
        }
    }

    func removeReplacementDirectory(_ directory: URL) throws { try FileManager.default.removeItem(at: directory) }
}

/// Called only from the store actor. An NSSavePanel grant authorizes one destination, not arbitrary
/// sibling names. Stage in the OS-provided replacement directory and publish through Foundation's
/// coordinated safe-save APIs while the caller holds the selected URL's security scope.
nonisolated struct NativeScreenRecordingExporter: Sendable {
    let files: any ScreenRecordingExportFileAccess

    init(files: any ScreenRecordingExportFileAccess = NativeScreenRecordingExportFileAccess()) { self.files = files }

    func export(source sourceURL: URL, identity: ScreenRecordingFileIdentity, to destination: URL) throws {
        try Task.checkCancellation()
        guard sourceURL.isFileURL, destination.isFileURL, identity.bytes > 0,
              identity.bytes <= 512 * 1_024 * 1_024 else { throw ScreenRecordingError.invalidArtifact }
        let source = Darwin.open(sourceURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard source >= 0 else { throw ScreenRecordingError.invalidArtifact }
        defer { Darwin.close(source) }
        guard try ScreenRecordingFileIdentity.read(descriptor: source) == identity else { throw ScreenRecordingError.invalidArtifact }
        let previous = try destinationIdentity(destination)
        let directory = try files.replacementDirectory(for: destination)
        let directoryIdentity = try replacementDirectoryIdentity(directory)
        var operationError: (any Error)?
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let staged = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
            let stagedIdentity = try copy(source: source, identity: identity, to: staged)
            try files.coordinateWrite(at: destination) { coordinatedURL in
                try Task.checkCancellation()
                guard coordinatedURL.standardizedFileURL == destination.standardizedFileURL,
                      try destinationIdentity(coordinatedURL) == previous,
                      try replacementDirectoryIdentity(directory) == directoryIdentity,
                      try ScreenRecordingFileIdentity.read(at: staged) == stagedIdentity,
                      try ScreenRecordingFileIdentity.read(at: sourceURL) == identity,
                      try ScreenRecordingFileIdentity.read(descriptor: source) == identity else {
                    throw ScreenRecordingError.exportFailed
                }
                try files.publish(staged, to: coordinatedURL, replacing: previous != nil)
                // Once Foundation commits the complete output, cancellation must not report it as undone.
            }
        } catch { operationError = error }
        // Cleanup failures propagate; do not claim that temporary video bytes were removed.
        guard try replacementDirectoryIdentity(directory) == directoryIdentity else { throw ScreenRecordingError.exportFailed }
        try files.removeReplacementDirectory(directory)
        if let operationError { throw operationError }
    }

    private func copy(source: Int32, identity: ScreenRecordingFileIdentity, to staged: URL) throws -> ScreenRecordingFileIdentity {
        try Task.checkCancellation()
        let output = Darwin.open(staged.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw ScreenRecordingError.exportFailed }
        defer { Darwin.close(output) }
        guard fchmod(output, 0o600) == 0 else { throw ScreenRecordingError.exportFailed }
        var buffer = [UInt8](repeating: 0, count: 1_024 * 1_024)
        var copied: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(source, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw ScreenRecordingError.exportFailed }
            if count == 0 { break }
            copied += Int64(count)
            guard copied <= identity.bytes else { throw ScreenRecordingError.invalidArtifact }
            try buffer.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { throw ScreenRecordingError.exportFailed }
                var offset = 0
                while offset < count {
                    try Task.checkCancellation()
                    let written = Darwin.write(output, base.advanced(by: offset), count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { throw ScreenRecordingError.exportFailed }
                    offset += written
                }
            }
        }
        guard copied == identity.bytes, try ScreenRecordingFileIdentity.read(descriptor: source) == identity,
              fsync(output) == 0 else { throw ScreenRecordingError.invalidArtifact }
        try Task.checkCancellation()
        return try ScreenRecordingFileIdentity.read(descriptor: output)
    }

    private func replacementDirectoryIdentity(_ url: URL) throws -> DirectoryIdentity {
        var value = stat()
        guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw ScreenRecordingError.exportFailed }
        return DirectoryIdentity(device: UInt64(value.st_dev), inode: UInt64(value.st_ino))
    }

    private struct DirectoryIdentity: Equatable { let device: UInt64; let inode: UInt64 }

    private func destinationIdentity(_ url: URL) throws -> ScreenRecordingFileIdentity? {
        var value = stat()
        if lstat(url.path, &value) != 0 {
            guard errno == ENOENT else { throw ScreenRecordingError.exportFailed }
            return nil
        }
        // Do not follow or replace a symlink, directory, package, or other unexpected item.
        guard value.st_mode & S_IFMT == S_IFREG else { throw ScreenRecordingError.exportFailed }
        return try ScreenRecordingFileIdentity.read(at: url)
    }
}
