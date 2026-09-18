import Foundation

/// The in-memory result of separating an image's foreground from its background.
public struct BackgroundRemovalResult: Sendable, Equatable {
    /// Bounded PNG preview of the original image for the active launcher session.
    public let sourcePreviewPNGData: Data
    /// Bounded PNG preview of the transparent result for the active launcher session.
    public let transparentPreviewPNGData: Data
    /// PNG bytes containing the foreground and a transparent background.
    public let transparentPNGData: Data
    /// Privacy-safe display name derived from the explicitly selected source URL.
    public let sourceFilename: String
    /// Width of the processed image in pixels.
    public let pixelWidth: Int
    /// Height of the processed image in pixels.
    public let pixelHeight: Int

    /// Creates a completed background-removal result.
    public init(
        sourcePreviewPNGData: Data,
        transparentPreviewPNGData: Data,
        transparentPNGData: Data,
        sourceFilename: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.sourcePreviewPNGData = sourcePreviewPNGData
        self.transparentPreviewPNGData = transparentPreviewPNGData
        self.transparentPNGData = transparentPNGData
        self.sourceFilename = sourceFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Typed failures produced while reading, segmenting, or encoding an image.
public enum BackgroundRemovalError: Error, Sendable, Equatable {
    /// The selected file could not be read as a supported image.
    case invalidImage
    /// No distinct foreground subject was found in the image.
    case noForegroundFound
    /// Vision could not create a usable foreground mask.
    case segmentationFailed
    /// The transparent result could not be encoded as PNG.
    case encodingFailed
    /// The selected file could not be read.
    case fileReadFailed
}

/// On-device image-segmentation boundary used by Background Remover.
public protocol BackgroundRemoving: Sendable {
    /// Removes the background from one explicitly selected image URL.
    func removeBackground(from sourceURL: URL) async throws -> BackgroundRemovalResult
}
