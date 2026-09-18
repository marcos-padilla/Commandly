#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

@MainActor
enum GIFSearchDebugFixture {
    static func services(exporter: any GIFExporting = NativeGIFExporter()) -> GIFSearchApplicationServices {
        .init(catalog: GeneratedGIFCatalog(), decoder: GIFAnimationDecoder(), exporter: exporter,
              openURL: { _ in }, fixtureLabel: "Generated UI Fixture — no GIPHY request or credentials")
    }
}
/// Four original geometric frames; used to verify animation and native copy/save without remote media.
actor GeneratedGIFData {
    func make(frameCount: Int = 4, width: Int = 120, height: Int = 80) throws -> Data {
        guard (1...1_001).contains(frameCount), (1...2_048).contains(width), (1...2_048).contains(height) else { throw GIFSearchError.invalidGIF }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, frameCount, nil),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GIFSearchError.invalidGIF }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frameCount {
            try Task.checkCancellation()
            context.setFillColor(CGColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.3, green: 0.8, blue: 0.75, alpha: 1))
            let side = max(1, min(width, height) / 3)
            context.fillEllipse(in: CGRect(x: (frame * max(1, width / 5)) % max(1, width - side), y: (height - side) / 2, width: side, height: side))
            guard let image = context.makeImage() else { throw GIFSearchError.invalidGIF }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw GIFSearchError.invalidGIF }
        return data as Data
    }
}
private actor GeneratedGIFCatalog {
    private var state = GIFConnectionState(revision: UUID(), isConfigured: true)
    private let data = GeneratedGIFData()
    func connection() -> GIFConnectionState { state }
    func configure(key: String) -> GIFConnectionState { state = .init(revision: UUID(), isConfigured: true); return state }
    func disconnect() -> GIFConnectionState { state = .init(revision: UUID(), isConfigured: false); return state }
    func search(_ query: GIFCatalogQuery, rating: GIFContentRating, offset: Int, connection: UUID) throws -> GIFCatalogPage {
        guard state.isConfigured, state.revision == connection else { throw GIFSearchError.changedConnection }
        let names = ["Generated celebration", "Generated welcome", "Generated thinking"]
        let items = names.enumerated().map { index, title in
            GIFCatalogItem(id: String(index), title: title, accessibilityText: "Original generated animation of a moving teal circle", creator: "Commandly Generated Fixture",
                           sourceName: nil, pageURL: nil, sourceURL: nil,
                           previewURL: URL(string: "https://media.giphy.com/media/commandly-generated-\(index)/200w.gif"),
                           originalURL: URL(string: "https://media.giphy.com/media/commandly-generated-\(index)/giphy.gif"))
        }
        return .init(items: items, nextOffset: nil)
    }
    func media(_ item: GIFCatalogItem, original: Bool, connection: UUID) async throws -> Data {
        guard state.isConfigured, state.revision == connection else { throw GIFSearchError.changedConnection }
        let bytes = try await data.make()
        try Task.checkCancellation()
        guard state.isConfigured, state.revision == connection else { throw GIFSearchError.changedConnection }
        return bytes
    }
}
extension GeneratedGIFCatalog: GIFCatalogServing {}
#endif
