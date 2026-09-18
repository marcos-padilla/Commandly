import Foundation

/// A camera available after explicit permission and preview activation.
public struct CameraDevice: Sendable, Equatable, Identifiable {
    /// Native device identity, retained only for the active camera session.
    public let id: String
    /// User-visible device name. Device identities and names must never be logged.
    public let name: String
    /// Creates a camera description.
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// One bounded immutable BGRA preview frame. It contains no audio or native capture references.
public struct CameraPreviewFrame: Sendable, Equatable {
    /// Packed BGRA bytes, with an ignored alpha channel; never persisted automatically.
    public let data: Data
    /// Frame width in pixels, at most 960.
    public let pixelWidth: Int
    /// Frame height in pixels, at most 960.
    public let pixelHeight: Int
    /// Packed row stride, exactly four bytes per pixel.
    public var bytesPerRow: Int { pixelWidth * 4 }
    /// Creates a bounded frame, rejecting inconsistent byte counts before presentation.
    public init(data: Data, pixelWidth: Int, pixelHeight: Int) throws {
        guard (1...960).contains(pixelWidth), (1...960).contains(pixelHeight),
              data.count == pixelWidth * pixelHeight * 4 else { throw CameraCaptureError.invalidFrame }
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// A metadata-stripped still photo held only for explicit review, copy, or export.
public struct CameraPhoto: Sendable, Equatable {
    /// Freshly encoded sRGB PNG bytes.
    public let pngData: Data
    /// A PNG preview at most 960 pixels on its longest edge.
    public let previewPNGData: Data
    /// Final photo width after orientation and optional mirroring.
    public let pixelWidth: Int
    /// Final photo height after orientation and optional mirroring.
    public let pixelHeight: Int
    /// Creates a completed, independently encoded photo.
    public init(pngData: Data, previewPNGData: Data, pixelWidth: Int, pixelHeight: Int) {
        self.pngData = pngData
        self.previewPNGData = previewPNGData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Privacy-safe recoverable camera failures without device names, frames, or native error details.
public enum CameraCaptureError: Error, Sendable, Equatable {
    /// Camera permission must be explicitly granted before a capture input is created.
    case permissionRequired
    /// No supported camera is currently connected.
    case noCamera
    /// The selected camera is no longer connected.
    case deviceUnavailable
    /// The camera session could not be configured or started.
    case startFailed
    /// Another app or system condition interrupted the session.
    case interrupted
    /// A capture requires an active preview with no other photo pending.
    case captureUnavailable
    /// Native photo capture could not produce image data.
    case captureFailed
    /// Captured image data could not be rendered as a safe PNG.
    case encodingFailed
    /// The preview frame's dimensions or byte count are invalid.
    case invalidFrame
    /// The system pasteboard could not accept the requested image copy.
    case copyFailed
}

/// Events from the active preview. Consumers discard events after session replacement or stop.
public enum CameraCaptureEvent: Sendable, Equatable {
    /// A new bounded frame replaces the preceding frame.
    case frame(CameraPreviewFrame)
    /// A recoverable native failure has stopped this session.
    case failed(CameraCaptureError)
    /// Capture has stopped and the stream will finish.
    case stopped
}

/// Metadata and a bounded live stream returned only after explicit camera activation.
public struct CameraCaptureSession: Sendable {
    /// Currently available cameras, for the session's device picker.
    public let devices: [CameraDevice]
    /// The camera selected for this session.
    public let selectedDeviceID: String
    /// Preview events. Production buffers only the newest frame.
    public let events: AsyncStream<CameraCaptureEvent>
    /// Creates a started-session value.
    public init(devices: [CameraDevice], selectedDeviceID: String, events: AsyncStream<CameraCaptureEvent>) {
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        self.events = events
    }
}

/// Native video-only preview and still capture. Creating the adapter must not access the camera.
public protocol CameraCapturing: Sendable {
    /// Starts a preview after explicit intent and previously granted camera permission.
    func start(deviceID: String?) async throws -> CameraCaptureSession
    /// Captures one reviewed-intent still, applying the user's mirroring choice to the pixels.
    func takePhoto(mirrored: Bool) async throws -> CameraPhoto
    /// Stops capture, finishes the event stream, and releases native device resources.
    func stop() async
}

/// Explicit copying of reviewed photo bytes, with no pasteboard reads.
public protocol CameraPhotoCopying: Sendable {
    /// Copies one PNG only after a user selects Copy Photo.
    func copyPNG(_ data: Data) async throws
}
