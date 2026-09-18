import AVFoundation
import Darwin
import Foundation
import Infrastructure

nonisolated protocol ScreenRecordingValidating: Sendable {
    func isPlayableVideo(at url: URL) async throws -> Bool
}

nonisolated struct NativeScreenRecordingValidator: ScreenRecordingValidating {
    func isPlayableVideo(at url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { return false }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        return !tracks.isEmpty
    }
}

/// Only this actor touches staging and export files. A private directory and an advisory lifetime
/// lock distinguish our abandoned crash remnants from another Commandly process's active output.
actor NativeScreenRecordingStore: ScreenRecordingStoring {
    private let root: URL
    private let validator: any ScreenRecordingValidating
    private let freeBytes: @Sendable (URL) throws -> Int64
    private var directory: URL?
    private var lease: Int32 = -1
    private var owned: [UUID: ScreenRecordingDraft] = [:]
    private var reviewed: [UUID: ScreenRecordingFileIdentity] = [:]
    private let exporter: NativeScreenRecordingExporter

    init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("com.commandly.screen-recordings", isDirectory: true),
         validator: any ScreenRecordingValidating = NativeScreenRecordingValidator(),
         exporter: NativeScreenRecordingExporter = NativeScreenRecordingExporter(),
         freeBytes: @escaping @Sendable (URL) throws -> Int64 = { url in
             let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
             guard let capacity = values.volumeAvailableCapacityForImportantUsage else { throw ScreenRecordingError.storageUnavailable }
             return capacity
         }) {
        self.root = root.standardizedFileURL
        self.validator = validator
        self.exporter = exporter
        self.freeBytes = freeBytes
    }

    deinit { if lease >= 0 { Darwin.close(lease) } }

    func prepare(container: ScreenRecordingContainer, limits: ScreenRecordingLimits) throws -> ScreenRecordingDraft {
        try Task.checkCancellation()
        guard owned.isEmpty else { throw ScreenRecordingError.busy }
        do {
            try makeDirectoryIfNeeded()
            guard try freeBytes(root) >= limits.requiredFreeBytes else { throw ScreenRecordingError.insufficientDiskSpace }
            guard let directory else { throw ScreenRecordingError.storageUnavailable }
            let id = UUID()
            let draft = ScreenRecordingDraft(id: id, url: directory.appendingPathComponent(id.uuidString).appendingPathExtension(container.rawValue), container: container)
            owned[id] = draft
            return draft
        } catch let error as ScreenRecordingError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw ScreenRecordingError.storageUnavailable }
    }

    func finalize(_ draft: ScreenRecordingDraft, summary: ScreenRecordingSummary,
                  limits: ScreenRecordingLimits) async throws -> ScreenRecordingArtifact {
        try Task.checkCancellation()
        try validateOwnership(draft)
        do {
            let values = try draft.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = values.fileSize, bytes > 0 else { throw ScreenRecordingError.invalidArtifact }
            guard Int64(bytes) <= limits.maximumArtifactBytes else { throw ScreenRecordingError.artifactTooLarge }
            guard summary.duration.isFinite, summary.duration > 0, summary.pixelWidth > 0, summary.pixelHeight > 0 else {
                throw ScreenRecordingError.invalidArtifact
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: draft.url.path)
            let identity = try ScreenRecordingFileIdentity.read(at: draft.url)
            guard identity.bytes == Int64(bytes), try await validator.isPlayableVideo(at: draft.url) else { throw ScreenRecordingError.invalidArtifact }
            try Task.checkCancellation()
            try validateOwnership(draft)
            guard try ScreenRecordingFileIdentity.read(at: draft.url) == identity else { throw ScreenRecordingError.invalidArtifact }
            reviewed[draft.id] = identity
            return ScreenRecordingArtifact(draft: draft, summary: ScreenRecordingSummary(
                duration: summary.duration, fileBytes: Int64(bytes), pixelWidth: summary.pixelWidth,
                pixelHeight: summary.pixelHeight, stopReason: summary.stopReason))
        } catch let error as ScreenRecordingError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw ScreenRecordingError.invalidArtifact }
    }

    func export(_ artifact: ScreenRecordingArtifact, to destination: URL) throws {
        try Task.checkCancellation()
        try validateOwnership(artifact.draft)
        guard let identity = reviewed[artifact.draft.id], identity.bytes == artifact.summary.fileBytes, destination.isFileURL,
              !destination.standardizedFileURL.path.hasPrefix(root.path + "/") else { throw ScreenRecordingError.exportFailed }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        do { try exporter.export(source: artifact.draft.url, identity: identity, to: destination.standardizedFileURL) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ScreenRecordingError.exportFailed }
    }

    func discard(_ draft: ScreenRecordingDraft) throws {
        try validateOwnership(draft)
        do {
            guard Darwin.unlink(draft.url.path) == 0 || errno == ENOENT else { throw ScreenRecordingError.storageUnavailable }
            owned.removeValue(forKey: draft.id)
            reviewed.removeValue(forKey: draft.id)
        } catch { throw ScreenRecordingError.storageUnavailable }
    }

    private func validateOwnership(_ draft: ScreenRecordingDraft) throws {
        guard owned[draft.id] == draft, let directory,
              draft.url.deletingLastPathComponent().standardizedFileURL == directory,
              draft.url.lastPathComponent == "\(draft.id.uuidString).\(draft.container.rawValue)" else {
            throw ScreenRecordingError.invalidArtifact
        }
    }

    private func makeDirectoryIfNeeded() throws {
        guard directory == nil else { return }
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw ScreenRecordingError.storageUnavailable }
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let maintenance = Darwin.open(root.appendingPathComponent(".maintenance").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard maintenance >= 0 else { throw ScreenRecordingError.storageUnavailable }
        defer { Darwin.close(maintenance) }
        guard flock(maintenance, LOCK_EX | LOCK_NB) == 0 else { throw ScreenRecordingError.busy }
        // Only our UUID directories containing an unlocked ownership file can be removed. Symlinks
        // and arbitrary siblings are never traversed. The lock is released automatically on crash.
        for child in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            try Task.checkCancellation()
            guard UUID(uuidString: child.lastPathComponent) != nil else { continue }
            let childValues = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard childValues.isDirectory == true, childValues.isSymbolicLink != true else { continue }
            let lock = Darwin.open(child.appendingPathComponent(".owner").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard lock >= 0 else { continue }
            defer { Darwin.close(lock) }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { continue }
            try files.removeItem(at: child)
        }
        let candidate = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: candidate, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let lock = Darwin.open(candidate.appendingPathComponent(".owner").path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else {
            try files.removeItem(at: candidate)
            throw ScreenRecordingError.storageUnavailable
        }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lock)
            try files.removeItem(at: candidate)
            throw ScreenRecordingError.storageUnavailable
        }
        directory = candidate
        lease = lock
    }

}
