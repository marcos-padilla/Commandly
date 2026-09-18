import Foundation

/// The explicit analysis requested for a user-selected still image.
public enum ImageRecognitionMode: String, Sendable, Equatable {
    /// Recognize readable text without uploading the image.
    case text
    /// Decode QR payloads without interpreting or opening them.
    case qr
}

/// Bounded analysis output retained only for the active image session.
public struct ImageRecognitionResult: Sendable, Equatable {
    /// Recognized text in the order returned by the recognition engine.
    public let text: String
    /// Distinct QR text payloads, preserved exactly rather than treated as commands.
    public let qrPayloads: [String]
    /// True when some text or QR results were omitted to stay within limits.
    public let isTruncated: Bool
    /// QR codes that were detected but did not contain a readable text payload.
    public let nonTextQRCodeCount: Int

    /// Creates a recognition result; no result itself performs a pasteboard or URL action.
    public init(text: String = "", qrPayloads: [String] = [], isTruncated: Bool = false, nonTextQRCodeCount: Int = 0) {
        self.text = text
        self.qrPayloads = qrPayloads
        self.isTruncated = isTruncated
        self.nonTextQRCodeCount = nonTextQRCodeCount
    }
}

/// Typed failures from native text or QR recognition.
public enum ImageRecognitionError: Error, Sendable, Equatable {
    /// The on-device recognition engine could not complete this image.
    case recognitionFailed
}

/// Native analysis of an explicitly selected image with no network or implicit copying/opening.
public protocol ImageRecognizing: Sendable {
    /// Reads pixels from the in-memory source and returns bounded text or QR payloads.
    /// Implementations revalidate source bytes and check cancellation around native work.
    func recognize(_ source: ImageConversionSource, mode: ImageRecognitionMode) async throws -> ImageRecognitionResult
}
