import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

@Suite("Byte-only native image conversion", .timeLimit(.minutes(1)))
struct NativeImageDataConversionTests {
    @Test
    func dataBoundaryRevalidatesBytesDimensionsAndSingleFrameWithoutAnyPath() async throws {
        let converter = NativeImageConversionService()
        await #expect(throws: ImageConversionError.invalidImage) { try await converter.convertImageData(Data("not an image".utf8), options: .init()) }
        let image = try FinderAIImageTestFiles.png()
        var oversized = image
        oversized.append(Data(count: 64 * 1_024 * 1_024 + 1 - oversized.count))
        await #expect(throws: ImageConversionError.inputTooLarge) { try await converter.convertImageData(oversized, options: .init()) }
        await #expect(throws: ImageConversionError.invalidDimensions) { try await converter.convertImageData(image, options: .init(longestEdge: 16_385)) }
        await #expect(throws: ImageConversionError.outputTooLarge) { try await converter.convertImageData(image, options: .init(longestEdge: 16_384)) }
        let source = try #require(CGImageSourceCreateWithData(image as CFData, nil))
        let multiPage = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(multiPage, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        #expect(CGImageDestinationFinalize(destination))
        await #expect(throws: ImageConversionError.animatedImageUnsupported) {
            try await converter.convertImageData(multiPage as Data, options: .init())
        }
    }

    @Test
    func cancelledByteOnlyRequestNeverReturnsEncodedOutput() async throws {
        let converter = NativeImageConversionService()
        let data = try FinderAIImageTestFiles.png()
        let task = Task { try await converter.convertImageData(data, options: .init()) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
