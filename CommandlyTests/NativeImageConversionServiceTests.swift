import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

struct NativeImageConversionServiceTests {
    @Test
    func nativePNGConversionResizesRotatesPreservesAlphaAndNeverChangesSource() async throws {
        let fixture = try ImageToolsFixture(width: 96, height: 48)
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let source = try await service.loadImage(from: fixture.url)
        #expect(source.pixelWidth == 96 && source.pixelHeight == 48)
        let output = try await service.convert(source, options: ImageConversionOptions(format: .png, longestEdge: 48, clockwiseQuarterTurns: 1))
        #expect(output.pixelWidth == 24 && output.pixelHeight == 48)
        let decoded = try ImageToolsFixture.decode(output.data)
        #expect(decoded.width == 24 && decoded.height == 48)
        #expect(try Data(contentsOf: fixture.url) == fixture.original)
        let bytes = try ImageToolsFixture.rgba(decoded)
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        #expect(alpha.contains(0))
        #expect(alpha.contains(255))
    }

    @Test
    func JPEGFlattensTransparencyOnWhiteAndDropsSourceMetadata() async throws {
        let fixture = try ImageToolsFixture(width: 96, height: 64, type: .tiff, metadata: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "private fixture comment"]
        ])
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let source = try await service.loadImage(from: fixture.url)
        let output = try await service.convert(source, options: ImageConversionOptions(format: .jpeg))
        let decoded = try ImageToolsFixture.decode(output.data)
        let bytes = try ImageToolsFixture.rgba(decoded)
        let rightPixel = (decoded.width - 1) * 4
        #expect(bytes[rightPixel] > 245 && bytes[rightPixel + 1] > 245 && bytes[rightPixel + 2] > 245)
        #expect(bytes[rightPixel + 3] == 255)
        let imageSource = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFImageDescription] == nil)
    }

    @Test
    func orientationIsAppliedBeforeAspectPreservingResizeAndPreviewIsBounded() async throws {
        let fixture = try ImageToolsFixture(width: 1_200, height: 600, type: .tiff, metadata: [kCGImagePropertyOrientation: 6])
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let source = try await service.loadImage(from: fixture.url)
        #expect(source.pixelWidth == 600 && source.pixelHeight == 1_200)
        let preview = try ImageToolsFixture.decode(source.previewPNGData)
        #expect(preview.width == 480 && preview.height == 960)
        let result = try await service.convert(source, options: ImageConversionOptions(format: .png, longestEdge: 300))
        #expect(result.pixelWidth == 150 && result.pixelHeight == 300)
        let output = try ImageToolsFixture.decode(result.data)
        #expect(output.width == 150 && output.height == 300)
    }

    @Test
    func allAdvertisedOutputFormatsProduceDecodablePixels() async throws {
        let fixture = try ImageToolsFixture(width: 96, height: 64)
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let formats = await service.supportedFormats()
        #expect(formats.contains(.png) && formats.contains(.jpeg) && formats.contains(.tiff))
        let source = try await service.loadImage(from: fixture.url)
        for format in formats {
            let output = try await service.convert(source, options: ImageConversionOptions(format: format))
            let decoded = try ImageToolsFixture.decode(output.data)
            #expect(decoded.width == 96 && decoded.height == 64)
            #expect(output.format == format)
        }
    }

    @Test
    func invalidDimensionsAndPixelLimitsAreRejectedBeforeOutputAllocation() async throws {
        let fixture = try ImageToolsFixture(width: 96, height: 64)
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let source = try await service.loadImage(from: fixture.url)
        for edge in [0, -1, 16_385, Int.max] {
            await #expect(throws: ImageConversionError.invalidDimensions) {
                try await service.convert(source, options: ImageConversionOptions(longestEdge: edge))
            }
        }
        await #expect(throws: ImageConversionError.outputTooLarge) {
            try await service.convert(source, options: ImageConversionOptions(longestEdge: 16_384))
        }
        await #expect(throws: ImageConversionError.invalidDimensions) {
            try await service.convert(source, options: ImageConversionOptions(clockwiseQuarterTurns: -1))
        }
    }

    @Test
    func malformedRemoteAnimatedAndOversizedSourcesAreRejected() async throws {
        let fixture = try ImageToolsFixture(width: 96, height: 64)
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let invalid = fixture.directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        await #expect(throws: ImageConversionError.invalidImage) { try await service.loadImage(from: invalid) }
        let remote = try #require(URL(string: "https://example.invalid/image.png"))
        await #expect(throws: ImageConversionError.fileReadFailed) { try await service.loadImage(from: remote) }
        let oversized = fixture.directory.appendingPathComponent("oversized.png")
        try Data().write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(64 * 1_024 * 1_024 + 1))
        try handle.close()
        await #expect(throws: ImageConversionError.inputTooLarge) { try await service.loadImage(from: oversized) }
        let animated = try ImageToolsFixture(width: 4, height: 4, type: .gif, frameCount: 2)
        defer { animated.cleanup() }
        await #expect(throws: ImageConversionError.animatedImageUnsupported) { try await service.loadImage(from: animated.url) }
        let wide = try ImageToolsFixture(width: 16_385, height: 1)
        defer { wide.cleanup() }
        await #expect(throws: ImageConversionError.inputTooLarge) { try await service.loadImage(from: wide.url) }
    }

    @Test
    func aPrecancelledRequestDoesNotReadOrDecode() async throws {
        let fixture = try ImageToolsFixture(width: 96, height: 64)
        defer { fixture.cleanup() }
        let service = NativeImageConversionService()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.loadImage(from: fixture.url)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

private struct ImageToolsFixture {
    let directory: URL
    let url: URL
    let original: Data

    init(width: Int, height: Int, type: UTType = .png, frameCount: Int = 1, metadata: [CFString: Any] = [:]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("commandly-image-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("source.\(type.preferredFilenameExtension ?? "image")")
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width / 2), height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frameCount, nil))
        for _ in 0..<frameCount { CGImageDestinationAddImage(destination, image, metadata as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination))
        original = data as Data
        try original.write(to: url)
    }

    func cleanup() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove generated image test directory") }
    }

    static func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
