import Foundation

/// Explicitly selected content; no background screen enumeration is required.
nonisolated public enum ScreenRecordingSource: String, CaseIterable, Sendable {
    case window, display
}

/// Microphone recording is deliberately separate from this screen recorder.
nonisolated public enum ScreenRecordingAudio: String, CaseIterable, Sendable {
    case none, systemAudio
}

nonisolated public enum ScreenRecordingContainer: String, CaseIterable, Sendable {
    case mp4, mov
}

nonisolated public enum ScreenRecordingCodec: String, CaseIterable, Sendable {
    case h264, hevc
}

nonisolated public enum ScreenRecordingResolution: String, CaseIterable, Sendable {
    case hd720, fullHD
}

/// Settings are frozen for one capture and displayed before selection and while recording.
nonisolated public struct ScreenRecordingOptions: Equatable, Sendable {
    public var source: ScreenRecordingSource
    public var audio: ScreenRecordingAudio
    public var container: ScreenRecordingContainer
    public var codec: ScreenRecordingCodec
    public var resolution: ScreenRecordingResolution
    public var showsCursor: Bool

    public init(source: ScreenRecordingSource = .window, audio: ScreenRecordingAudio = .none,
                container: ScreenRecordingContainer = .mp4, codec: ScreenRecordingCodec = .h264,
                resolution: ScreenRecordingResolution = .fullHD, showsCursor: Bool = true) {
        self.source = source
        self.audio = audio
        self.container = container
        self.codec = codec
        self.resolution = resolution
        self.showsCursor = showsCursor
    }
}

/// Conservative stop thresholds reserve room for native encoder buffering/finalization.
/// The framework does not expose an exact hard write cap; final artifact validation is separate.
nonisolated public struct ScreenRecordingLimits: Equatable, Sendable {
    public let maximumDuration: TimeInterval
    public let stopFileBytes: Int64
    public let maximumArtifactBytes: Int64
    public let requiredFreeBytes: Int64

    public init(maximumDuration: TimeInterval = 600, stopFileBytes: Int64 = 384 * 1_024 * 1_024,
                maximumArtifactBytes: Int64 = 512 * 1_024 * 1_024, requiredFreeBytes: Int64 = 768 * 1_024 * 1_024) {
        self.maximumDuration = maximumDuration
        self.stopFileBytes = stopFileBytes
        self.maximumArtifactBytes = maximumArtifactBytes
        self.requiredFreeBytes = requiredFreeBytes
    }
}

nonisolated public enum ScreenRecordingStopReason: Equatable, Sendable {
    case user, durationLimit, sizeLimit
}

nonisolated public struct ScreenRecordingProgress: Equatable, Sendable {
    public let duration: TimeInterval
    public let fileBytes: Int64
    public init(duration: TimeInterval, fileBytes: Int64) { self.duration = duration; self.fileBytes = fileBytes }
}

/// Final native metadata. A finished callback, not Stop being requested, authorizes review.
nonisolated public struct ScreenRecordingSummary: Equatable, Sendable {
    public let duration: TimeInterval
    public let fileBytes: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let stopReason: ScreenRecordingStopReason
    public init(duration: TimeInterval, fileBytes: Int64, pixelWidth: Int, pixelHeight: Int,
                stopReason: ScreenRecordingStopReason = .user) {
        self.duration = duration; self.fileBytes = fileBytes
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.stopReason = stopReason
    }
}

nonisolated public enum ScreenRecordingEvent: Equatable, Sendable {
    case started
    case progress(ScreenRecordingProgress)
    case stopping(ScreenRecordingStopReason)
    case stopNeedsAttention
    case finished(ScreenRecordingSummary)
    case failed(ScreenRecordingError)
    case cancelled
}

/// Typed messages never contain window titles, file paths, captured content or native error text.
nonisolated public enum ScreenRecordingError: Error, Equatable, Sendable {
    case busy, selectionUnavailable, selectionInvalid, permissionRequired
    case unsupportedConfiguration, startFailed, recordingFailed, interrupted, finalizationFailed
    case storageUnavailable, insufficientDiskSpace, artifactTooLarge, invalidArtifact, exportFailed
}

/// Owned local staging destination. The storage adapter validates ownership before every operation.
nonisolated public struct ScreenRecordingDraft: Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let container: ScreenRecordingContainer
    public init(id: UUID, url: URL, container: ScreenRecordingContainer) {
        self.id = id; self.url = url; self.container = container
    }
}

/// Session-only reviewed video reference; never log, encode or add its private URL to history.
nonisolated public struct ScreenRecordingArtifact: Equatable, Sendable {
    public let draft: ScreenRecordingDraft
    public let summary: ScreenRecordingSummary
    public init(draft: ScreenRecordingDraft, summary: ScreenRecordingSummary) { self.draft = draft; self.summary = summary }
}

/// A genuine recording stream; selection begins only after explicit user activation.
@MainActor
public protocol ScreenRecordingCapturing: AnyObject {
    func begin(options: ScreenRecordingOptions, destination: ScreenRecordingDraft,
               limits: ScreenRecordingLimits) async throws -> AsyncStream<ScreenRecordingEvent>
    /// Requests graceful stop; the event stream finishes only after the file has finalized.
    func stop() async
    /// Waits for native capture/output shutdown before returning. Safe to call repeatedly.
    func cancel() async
}

/// Private temporary video lifecycle and explicit, atomic user-selected export.
public protocol ScreenRecordingStoring: Sendable {
    func prepare(container: ScreenRecordingContainer, limits: ScreenRecordingLimits) async throws -> ScreenRecordingDraft
    func finalize(_ draft: ScreenRecordingDraft, summary: ScreenRecordingSummary,
                  limits: ScreenRecordingLimits) async throws -> ScreenRecordingArtifact
    func export(_ artifact: ScreenRecordingArtifact, to destination: URL) async throws
    func discard(_ draft: ScreenRecordingDraft) async throws
}
