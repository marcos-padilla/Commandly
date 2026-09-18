import Foundation

/// One explicit screenshot selection. No continuous recording is part of this contract.
public enum ScreenshotKind: String, Sendable, CaseIterable, Identifiable {
    /// The person selects one display in the system picker.
    case display
    /// The person selects one window in the system picker.
    case window
    /// The person draws one rectangular region after granting Screen Recording access.
    case region
    /// Stable identity for selection controls.
    public var id: String { rawValue }
}

/// Options applied to one explicitly selected screenshot.
public struct ScreenshotRequest: Sendable, Equatable {
    /// What the person intends to select.
    public let kind: ScreenshotKind
    /// Whether the screenshot should contain the cursor.
    public let showsCursor: Bool
    /// Creates a one-shot capture request.
    public init(kind: ScreenshotKind, showsCursor: Bool = false) { self.kind = kind; self.showsCursor = showsCursor }
}

/// A bounded reviewed screenshot artifact. Contains no window title, URL, device identity, or source coordinates.
/// Future consumers must separately obtain explicit intent before sending these bytes to an AI provider.
public struct ScreenshotImage: Sendable, Equatable, Identifiable {
    /// Ephemeral in-memory identity; it conveys no permission to recapture content.
    public let id: UUID
    /// Freshly rendered sRGB PNG bytes, at most 160 MiB.
    public let pngData: Data
    /// Bounded PNG preview, at most 8 MiB and 1,280 pixels on its longest edge in native adapters.
    public let previewPNGData: Data
    /// Source category, without identifying the captured content.
    public let kind: ScreenshotKind
    /// Final image width, at most 8,192 pixels.
    public let pixelWidth: Int
    /// Final image height, at most 8,192 pixels; total output is at most 40 megapixels.
    public let pixelHeight: Int
    /// Creates an artifact after validation. Empty or oversized byte buffers/dimensions are rejected.
    public init(id: UUID = UUID(), pngData: Data, previewPNGData: Data, kind: ScreenshotKind, pixelWidth: Int, pixelHeight: Int) throws {
        guard (1...8_192).contains(pixelWidth), (1...8_192).contains(pixelHeight),
              pixelWidth * pixelHeight <= 40_000_000,
              pngData.isEmpty == false, pngData.count <= 160 * 1_024 * 1_024,
              previewPNGData.isEmpty == false, previewPNGData.count <= 8 * 1_024 * 1_024 else {
            throw ScreenshotCaptureError.invalidImage
        }
        self.id = id
        self.pngData = pngData
        self.previewPNGData = previewPNGData
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Sanitized screenshot errors without private content or native error descriptions.
public enum ScreenshotCaptureError: Error, Sendable, Equatable {
    /// The person dismissed the selection UI.
    case cancelled
    /// Another explicit selection is already active.
    case busy
    /// Region capture requires Screen Recording access, or capture access was revoked.
    case permissionRequired
    /// The system cannot present a picker in the current session.
    case selectionUnavailable
    /// The selected display/window/region is unavailable or invalid.
    case selectionInvalid
    /// The native capture failed, possibly because content closed or is protected.
    case captureFailed
    /// Pixel/encoded bounds were invalid or encoding failed.
    case invalidImage
    /// The clipboard did not accept the image.
    case copyFailed
}

/// User-interactive, one-shot capture. Construction and app launch must not inspect or capture screen content.
@MainActor
public protocol ScreenshotCapturing: Sendable {
    /// Presents a new selection UI and captures only after the person chooses content.
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage
    /// Cancels selection/processing and prevents late content from reaching review.
    func cancel()
}

/// Writes a reviewed screenshot only when the person explicitly chooses Copy Screenshot.
public protocol ScreenshotCopying: Sendable {
    /// Copies PNG bytes without reading the clipboard.
    func copyPNG(_ data: Data) async throws
}
