import Foundation

/// Native output formats offered by Image Tools when an encoder is available on this Mac.
public enum ImageConversionFormat: String, CaseIterable, Sendable, Equatable, Identifiable {
    /// Lossless PNG with transparency.
    case png
    /// JPEG with transparent pixels composited on white.
    case jpeg
    /// HEIC with transparent pixels composited on white.
    case heic
    /// TIFF with transparency.
    case tiff

    /// Stable format identity for selection controls.
    public var id: String { rawValue }
    /// Human-readable format name.
    public var title: String { rawValue.uppercased() }
    /// Standard filename extension for this format.
    public var filenameExtension: String { self == .jpeg ? "jpg" : rawValue }
    /// Whether Commandly preserves transparency in this output format.
    public var preservesTransparency: Bool { self == .png || self == .tiff }
}

/// A bounded, explicitly chosen source image retained only for the active session.
public struct ImageConversionSource: Sendable, Equatable {
    /// Original compressed image bytes. Never uploaded or modified in place.
    public let data: Data
    /// Orientation-corrected thumbnail suitable for displaying without full-size decoding.
    public let previewPNGData: Data
    /// Display-only source filename, excluding its parent directory.
    public let filename: String
    /// Width after applying the image's orientation metadata.
    public let pixelWidth: Int
    /// Height after applying the image's orientation metadata.
    public let pixelHeight: Int

    /// Creates a source value for a native adapter or deterministic test double.
    public init(data: Data, previewPNGData: Data, filename: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.previewPNGData = previewPNGData
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Explicit conversion settings. Resizing always preserves the source aspect ratio.
public struct ImageConversionOptions: Sendable, Equatable {
    /// Requested native output encoding.
    public var format: ImageConversionFormat
    /// Target longest edge in pixels, or nil to keep the original dimensions.
    public var longestEdge: Int?
    /// Clockwise quarter turns. The adapter accepts values from zero through three.
    public var clockwiseQuarterTurns: Int

    /// Creates conversion settings with original dimensions and no rotation by default.
    public init(format: ImageConversionFormat = .png, longestEdge: Int? = nil, clockwiseQuarterTurns: Int = 0) {
        self.format = format
        self.longestEdge = longestEdge
        self.clockwiseQuarterTurns = clockwiseQuarterTurns
    }
}

/// Completed image bytes and a bounded preview, ready for explicit export.
public struct ImageConversionResult: Sendable, Equatable {
    /// Freshly encoded image data, without copied source metadata.
    public let data: Data
    /// Orientation-corrected preview, at most 960 pixels on its longest edge.
    public let previewPNGData: Data
    /// Format used for the encoded result.
    public let format: ImageConversionFormat
    /// Final output width including rotation.
    public let pixelWidth: Int
    /// Final output height including rotation.
    public let pixelHeight: Int

    /// Creates a completed result.
    public init(data: Data, previewPNGData: Data, format: ImageConversionFormat, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.previewPNGData = previewPNGData
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Recoverable failures at the native image conversion boundary.
public enum ImageConversionError: Error, Sendable, Equatable {
    /// The explicitly selected file could not be read.
    case fileReadFailed
    /// The data could not be decoded as a supported still image.
    case invalidImage
    /// Multiple frames or pages cannot be represented by this still-image workflow.
    case animatedImageUnsupported
    /// Source bytes or declared pixel dimensions exceed the service's limits.
    case inputTooLarge
    /// Requested dimensions or rotation are outside the supported range.
    case invalidDimensions
    /// Output dimensions, allocation, or encoded bytes exceed the service's limits.
    case outputTooLarge
    /// The current device cannot encode the selected output format.
    case unsupportedFormat
    /// ImageIO could not finish encoding the rendered pixels.
    case encodingFailed
}

/// Local image conversion with explicit source selection and no writes to the source.
public protocol ImageConverting: Sendable {
    /// Reports formats that this device can encode.
    func supportedFormats() async -> [ImageConversionFormat]
    /// Reads and validates one local image while holding its security scope.
    func loadImage(from url: URL) async throws -> ImageConversionSource
    /// Creates an independent encoded result, honoring cancellation between native operations.
    func convert(_ source: ImageConversionSource, options: ImageConversionOptions) async throws -> ImageConversionResult
}


/// Byte-only native conversion for a caller that already enforced its own file-read authority.
/// The adapter receives no path or bookmark, never writes a file, and revalidates all image bounds.
public protocol ImageDataConverting: Sendable {
    /// Reports native encoders available on this device without reading any source image.
    func supportedFormats() async -> [ImageConversionFormat]
    /// Converts bounded compressed bytes locally; the caller separately controls any output write.
    func convertImageData(_ data: Data, options: ImageConversionOptions) async throws -> ImageConversionResult
}
