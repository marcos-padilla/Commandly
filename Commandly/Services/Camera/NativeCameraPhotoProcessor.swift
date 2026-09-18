import Foundation
import Infrastructure

/// Byte-only boundary for still-photo processing; native image objects stay inside the worker.
nonisolated protocol CameraPhotoProcessing: Sendable {
    func render(_ data: Data, mirrored: Bool) async throws -> CameraPhoto
}

/// Independent of the capture executor so stopRunning can release the camera during encoding.
/// The caller owns the processing Task and cancellation reaches the synchronous renderer's checks.
actor NativeCameraPhotoProcessor: CameraPhotoProcessing {
    func render(_ data: Data, mirrored: Bool) throws -> CameraPhoto {
        try CameraPhotoRenderer.render(data, mirrored: mirrored)
    }
}
