import Darwin
import Foundation
import ImageIO
import Infrastructure
import OSLog
import UniformTypeIdentifiers

/// A deadline, not synchronization: production waits ten real minutes before retiring a handoff.
/// The injected equivalent lets tests advance time without sleeping or retaining private files.
nonisolated struct CleanShotLeaseClock: Sendable {
    var now: @Sendable () -> Date = { Date() }
    var waitUntil: @Sendable (Date) async throws -> Void = { deadline in
        let remaining = max(0, deadline.timeIntervalSinceNow)
        try await ContinuousClock().sleep(for: .seconds(remaining))
    }
}

nonisolated struct CleanShotFileLease: Sendable, Equatable {
    let id: UUID
    let fileURL: URL
}

/// Owns only UUID PNGs under a private temporary directory. No source file is opened or changed.
/// Successful dispatch retains its lease independently of launcher dismissal because CleanShot
/// does not document a file-consumed callback. Expired leftovers are swept on the next explicit
/// handoff after abnormal termination. Deletion is not a promise of secure disk erasure.
actor CleanShotTemporaryStore {
    nonisolated let rootURL: URL
    private let clock: CleanShotLeaseClock
    private let maximumFiles: Int
    private let maximumBytes: Int
    private let fileManager = FileManager()
    private let logger = Logger(subsystem: "com.businessmate360.Commandly", category: "CleanShotHandoff")
    private var deadlines: [UUID: Date] = [:]
    private var retirementTasks: [UUID: Task<Void, Never>] = [:]
    static let lifetime: TimeInterval = 600

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         clock: CleanShotLeaseClock = CleanShotLeaseClock(), maximumFiles: Int = 3,
         maximumBytes: Int = 320 * 1_024 * 1_024) {
        rootURL = temporaryDirectory.appendingPathComponent("Commandly-CleanShot-Handoff", isDirectory: true)
        self.clock = clock
        self.maximumFiles = maximumFiles
        self.maximumBytes = maximumBytes
    }

    func stage(_ image: ScreenshotImage) throws -> CleanShotFileLease {
        try Task.checkCancellation()
        try validatePNG(image)
        do {
            try prepareRoot()
            try removeExpiredFiles()
            let existing = try ownedFiles()
            let existingBytes = try existing.reduce(0) { result, file in
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                return result + ((attributes[.size] as? NSNumber)?.intValue ?? maximumBytes)
            }
            guard existing.count < maximumFiles, image.pngData.count <= maximumBytes,
                  existingBytes <= maximumBytes - image.pngData.count else { throw ScreenshotAnnotationError.temporaryStorageFull }
            let id = UUID()
            let lease = CleanShotFileLease(id: id, fileURL: rootURL.appendingPathComponent(id.uuidString).appendingPathExtension("png"))
            try writePrivate(image.pngData, to: lease.fileURL)
            do {
                try fileManager.setAttributes([.modificationDate: clock.now()], ofItemAtPath: lease.fileURL.path)
                try Task.checkCancellation()
            } catch {
                try fileManager.removeItem(at: lease.fileURL)
                throw error
            }
            let deadline = clock.now().addingTimeInterval(Self.lifetime)
            deadlines[id] = deadline
            let clock = self.clock
            // This tracked task intentionally keeps the store alive through the lease deadline,
            // even if CleanShot activation dismisses the launcher immediately after dispatch.
            retirementTasks[id] = Task { [self] in
                do {
                    try await clock.waitUntil(deadline)
                    try remove(lease)
                } catch is CancellationError {
                    // Explicit removal cancelled this exact lease's pending deadline.
                } catch {
                    logger.error("Could not retire a temporary CleanShot image; cleanup will retry on next handoff")
                }
            }
            return lease
        } catch is CancellationError { throw CancellationError() }
        catch let error as ScreenshotAnnotationError { throw error }
        catch { throw ScreenshotAnnotationError.temporaryStorageFailed }
    }

    func remove(_ lease: CleanShotFileLease) throws {
        guard lease.fileURL == rootURL.appendingPathComponent(lease.id.uuidString).appendingPathExtension("png") else {
            throw ScreenshotAnnotationError.temporaryStorageFailed
        }
        let directory = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if directory < 0 {
            guard errno == ENOENT else { throw ScreenshotAnnotationError.temporaryStorageFailed }
        } else {
            defer { Darwin.close(directory) }
            var metadata = stat()
            guard Darwin.fstat(directory, &metadata) == 0, metadata.st_uid == getuid(),
                  metadata.st_mode & 0o777 == 0o700 else { throw ScreenshotAnnotationError.temporaryStorageFailed }
            let result = Darwin.unlinkat(directory, lease.fileURL.lastPathComponent, 0)
            guard result == 0 || errno == ENOENT else { throw ScreenshotAnnotationError.temporaryStorageFailed }
        }
        deadlines[lease.id] = nil
        retirementTasks.removeValue(forKey: lease.id)?.cancel()
    }

    func removeExpiredFiles() throws {
        for file in try ownedFiles() {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                throw ScreenshotAnnotationError.temporaryStorageFailed
            }
            let attributes = try fileManager.attributesOfItem(atPath: file.path)
            guard let modified = attributes[.modificationDate] as? Date else { throw ScreenshotAnnotationError.temporaryStorageFailed }
            let deadline = deadlines[id] ?? modified.addingTimeInterval(Self.lifetime)
            if deadline <= clock.now() { try remove(CleanShotFileLease(id: id, fileURL: file)) }
        }
    }

    func waitForRetirementForTesting(_ lease: CleanShotFileLease) async {
        await retirementTasks[lease.id]?.value
    }

    private func prepareRoot() throws {
        let status = Darwin.mkdir(rootURL.path, 0o700)
        guard status == 0 || errno == EEXIST else { throw ScreenshotAnnotationError.temporaryStorageFailed }
        var metadata = stat()
        guard Darwin.lstat(rootURL.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR, metadata.st_uid == getuid(),
              metadata.st_mode & 0o777 == 0o700 else { throw ScreenshotAnnotationError.temporaryStorageFailed }
    }

    private func ownedFiles() throws -> [URL] {
        // Foundation may return /private/var URLs for a /var temporary root. Keep ownership
        // anchored to this store and use only each immediate entry's basename.
        let entries = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        let files = entries.map { rootURL.appendingPathComponent($0.lastPathComponent, isDirectory: false) }
        guard files.count <= 256 else { throw ScreenshotAnnotationError.temporaryStorageFull }
        for file in files {
            guard file.pathExtension == "png", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else {
                throw ScreenshotAnnotationError.temporaryStorageFailed
            }
            var metadata = stat()
            guard Darwin.lstat(file.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_nlink == 1, metadata.st_uid == getuid(), metadata.st_mode & 0o777 == 0o600,
                  metadata.st_size >= 0, metadata.st_size <= 160 * 1_024 * 1_024 else {
                throw ScreenshotAnnotationError.temporaryStorageFailed
            }
        }
        return files
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        let directory = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ScreenshotAnnotationError.temporaryStorageFailed }
        defer { Darwin.close(directory) }
        let descriptor = Darwin.openat(directory, url.lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ScreenshotAnnotationError.temporaryStorageFailed }
        defer { Darwin.close(descriptor) }
        do {
            try data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { throw ScreenshotAnnotationError.invalidImage }
                var written = 0
                while written < data.count {
                    try Task.checkCancellation()
                    let count = Darwin.write(descriptor, base.advanced(by: written), min(1_048_576, data.count - written))
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw ScreenshotAnnotationError.temporaryStorageFailed }
                    written += count
                }
            }
        } catch {
            guard Darwin.unlinkat(directory, url.lastPathComponent, 0) == 0 else { throw ScreenshotAnnotationError.temporaryStorageFailed }
            throw error
        }
    }

    private func validatePNG(_ image: ScreenshotImage) throws {
        guard image.pngData.count <= 160 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(image.pngData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == image.pixelWidth, height == image.pixelHeight else { throw ScreenshotAnnotationError.invalidImage }
    }
}
