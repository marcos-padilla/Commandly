import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

nonisolated struct GIFDecodedAnimation: Sendable, Identifiable {
    let id: UUID
    let frames: [CGImage]
    let frameEnds: [TimeInterval]
    let duration: TimeInterval
    let originalFrameCount: Int
    func frame(at elapsed: TimeInterval) -> CGImage? {
        guard !frames.isEmpty, duration.isFinite, duration > 0 else { return frames.first }
        let position = max(0, elapsed).truncatingRemainder(dividingBy: duration)
        let index = frameEnds.firstIndex { $0 > position } ?? 0
        return frames.indices.contains(index) ? frames[index] : frames.first
    }
}
nonisolated protocol GIFAnimationDecoding: Sendable {
    func preview(_ data: Data) async throws -> GIFDecodedAnimation
    func validateOriginal(_ data: Data) async throws
}
/// ImageIO parses and decodes on this actor. All retained preview pixels and frame counts are bounded.
actor GIFAnimationDecoder {
    func preview(_ data: Data) throws -> GIFDecodedAnimation {
        guard data.count <= 8 * 1_024 * 1_024 else { throw GIFSearchError.previewTooLarge }
        let source = try validatedSource(data)
        let count = CGImageSourceGetCount(source)
        guard count <= 400 else { throw GIFSearchError.previewTooLarge }
        var frames: [CGImage] = []; var ends: [TimeInterval] = []; var duration = 0.0; var decodedBytes = 0
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 360, kCGImageSourceShouldCacheImmediately: true]
        for index in 0..<count {
            try Task.checkCancellation()
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { throw GIFSearchError.invalidGIF }
            let cost = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
            guard !cost.overflow, cost.partialValue <= 48 * 1_024 * 1_024 - decodedBytes else { throw GIFSearchError.previewTooLarge }
            decodedBytes += cost.partialValue
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let raw = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            // Native/browser GIF playback treats tiny or absent delays as a human-viewable frame interval.
            let delay = raw.isFinite && raw >= 0.02 ? min(raw, 10) : 0.1
            duration += delay; frames.append(image); ends.append(duration)
        }
        try Task.checkCancellation()
        return .init(id: UUID(), frames: frames, frameEnds: ends, duration: duration, originalFrameCount: count)
    }
    func validateOriginal(_ data: Data) throws { _ = try validatedSource(data) }
    private func validatedSource(_ data: Data) throws -> CGImageSource {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 32 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source).map({ $0 as String }) == UTType.gif.identifier,
              CGImageSourceGetStatus(source) == .statusComplete else { throw GIFSearchError.invalidGIF }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { throw GIFSearchError.notAnimated }
        guard count <= 1_000 else { throw GIFSearchError.responseTooLarge }
        for index in 0..<count {
            try Task.checkCancellation()
            guard let value = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = (value[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (value[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  (1...8_192).contains(width), (1...8_192).contains(height),
                  width * height <= 16_777_216 else { throw GIFSearchError.invalidGIF }
        }
        return source
    }
}
extension GIFAnimationDecoder: GIFAnimationDecoding {}
