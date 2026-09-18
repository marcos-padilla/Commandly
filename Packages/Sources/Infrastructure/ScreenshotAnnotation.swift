import Foundation

/// A named, explicit handoff of a reviewed screenshot to CleanShot's local annotation editor.
/// It does not authorize screen capture, clipboard access, upload, or an AI request.
@MainActor
public protocol ScreenshotAnnotating: Sendable {
    /// Opens exactly these reviewed PNG bytes in CleanShot X. A successful return means the
    /// operating system accepted the handoff, not that CleanShot finished reading or editing it.
    /// Cancellation after native dispatch cannot retract the handoff or the recipient's copy.
    func openInCleanShot(_ image: ScreenshotImage) async throws
}

/// Recoverable, sanitized handoff failures without image bytes, file paths, or native messages.
public enum ScreenshotAnnotationError: Error, Sendable, Equatable {
    /// CleanShot's documented URL scheme has no installed handler.
    case applicationUnavailable
    /// The registered handler does not identify itself as CleanShot X.
    case unexpectedApplication
    /// The installed CleanShot version does not support the documented annotation action.
    case applicationOutdated
    /// Input was not a bounded PNG matching the reviewed artifact's dimensions.
    case invalidImage
    /// A private temporary file could not be written or removed safely.
    case temporaryStorageFailed
    /// Too many unexpired handoffs exist, or their combined bytes exceed the storage limit.
    case temporaryStorageFull
    /// The operating system rejected the local annotation handoff.
    case openFailed
}
