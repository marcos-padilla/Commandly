import CoreGraphics
import Foundation
import Infrastructure
import ScreenCaptureKit
import Synchronization

/// Native filter objects stay inside the callback. Only immutable CGImage or sanitized errors cross tasks.
nonisolated final class ScreenshotSystemPickerObserver: NSObject, SCContentSharingPickerObserver, Sendable {
    private let claimed = Mutex(false)
    private let request: ScreenshotRequest
    private let result: @Sendable (Result<CGImage, ScreenshotCaptureError>) -> Void
    init(request: ScreenshotRequest, result: @escaping @Sendable (Result<CGImage, ScreenshotCaptureError>) -> Void) {
        self.request = request
        self.result = result
    }
    func invalidate() { claimed.withLock { $0 = true } }
    private func claim() -> Bool {
        claimed.withLock { state in guard state == false else { return false }; state = true; return true }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil, claim() else { return }
        result(.failure(.cancelled))
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        guard claim() else { return }
        result(.failure(.selectionUnavailable))
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil, claim() else { return }
        guard (request.kind == .window && filter.style == .window) || (request.kind == .display && filter.style == .display) else {
            result(.failure(.selectionInvalid)); return
        }
        do {
            let configuration = try ScreenshotNativeConfiguration.make(points: filter.contentRect.size,
                scale: CGFloat(filter.pointPixelScale), showsCursor: request.showsCursor)
            SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration) { [result] output, error in
                if let error { result(.failure(ScreenshotNativeConfiguration.failure(error))); return }
                guard let image = output?.sdrImage else { result(.failure(.captureFailed)); return }
                result(.success(image))
            }
        } catch { result(.failure(.selectionInvalid)) }
    }
}

nonisolated enum ScreenshotNativeConfiguration {
    static func make(points: CGSize, scale: CGFloat, showsCursor: Bool) throws -> SCScreenshotConfiguration {
        let size = try ScreenshotGeometry.outputSize(points: points, scale: scale)
        let configuration = SCScreenshotConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = showsCursor
        configuration.ignoreShadows = true
        configuration.includeChildWindows = false
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local
        configuration.fileURL = nil
        return configuration
    }
    static func failure(_ error: Error) -> ScreenshotCaptureError {
        let native = error as NSError
        if native.domain == SCStreamErrorDomain {
            if native.code == SCStreamError.Code.userDeclined.rawValue { return .permissionRequired }
            if native.code == SCStreamError.Code.userStopped.rawValue { return .cancelled }
        }
        return .captureFailed
    }
}
