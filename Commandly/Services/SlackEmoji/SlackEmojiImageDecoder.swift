import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

nonisolated struct SlackEmojiImageInfo: Sendable, Equatable {
    let typeIdentifier: String
    let fileExtension: String
    let animated: Bool
}
nonisolated struct SlackEmojiPreview: Sendable, Identifiable {
    let id: UUID
    let image: CGImage
    let animation: GIFDecodedAnimation?
    let info: SlackEmojiImageInfo
}
nonisolated protocol SlackEmojiImageDecoding: Sendable {
    func inspect(_ data: Data) async throws -> SlackEmojiImageInfo
    func preview(_ data: Data) async throws -> SlackEmojiPreview
}
/// Validates untrusted Slack media off MainActor and reuses GIF's bounded native animation decoder.
actor SlackEmojiImageDecoder {
    private let gifs: any GIFAnimationDecoding
    init(gifs: any GIFAnimationDecoding = GIFAnimationDecoder()) { self.gifs = gifs }
    func inspect(_ data: Data) throws -> SlackEmojiImageInfo { try source(data).1 }
    func preview(_ data: Data) async throws -> SlackEmojiPreview {
        let (source, info) = try source(data)
        if info.animated {
            do {
                let animation = try await gifs.preview(data); try Task.checkCancellation()
                guard let frame = animation.frames.first else { throw SlackEmojiError.invalidImage }
                return .init(id: UUID(), image: frame, animation: animation, info: info)
            } catch is CancellationError { throw CancellationError() }
            catch GIFSearchError.previewTooLarge { throw SlackEmojiError.previewTooLarge }
            catch { throw SlackEmojiError.invalidImage }
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 360, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.bytesPerRow * image.height <= 4 * 1_024 * 1_024 else { throw SlackEmojiError.invalidImage }
        try Task.checkCancellation()
        return .init(id: UUID(), image: image, animation: nil, info: info)
    }
    private func source(_ data: Data) throws -> (CGImageSource, SlackEmojiImageInfo) {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 8 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let rawType = CGImageSourceGetType(source), CGImageSourceGetStatus(source) == .statusComplete else { throw SlackEmojiError.invalidImage }
        let type = rawType as String
        let fileExtension: String
        switch type {
        case UTType.gif.identifier: fileExtension = "gif"
        case UTType.png.identifier: fileExtension = "png"
        case UTType.jpeg.identifier: fileExtension = "jpg"
        default: throw SlackEmojiError.invalidImage
        }
        let count = CGImageSourceGetCount(source)
        guard (1...1_000).contains(count), type == UTType.gif.identifier || count == 1 else { throw SlackEmojiError.invalidImage }
        for index in 0..<count {
            try Task.checkCancellation()
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  (1...8_192).contains(width), (1...8_192).contains(height), width * height <= 16_777_216 else { throw SlackEmojiError.invalidImage }
        }
        return (source, .init(typeIdentifier: type, fileExtension: fileExtension, animated: count > 1))
    }
}
extension SlackEmojiImageDecoder: SlackEmojiImageDecoding {}
