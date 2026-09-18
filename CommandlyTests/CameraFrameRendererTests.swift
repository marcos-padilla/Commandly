import CoreGraphics
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct CameraFrameRendererTests {
    @Test
    func generatedPixelsKeepColorsAndDimensionsAcrossThePreviewBoundary() throws {
        let source = try image(width: 2, height: 1, bytes: [255, 0, 0, 255, 0, 0, 255, 255])
        let frame = try CameraFrameRenderer.frame(from: source)
        #expect(frame.pixelWidth == 2 && frame.pixelHeight == 1 && frame.bytesPerRow == 8)
        #expect(Array(frame.data.prefix(3)) == [0, 0, 255])
        #expect(Array(frame.data[4..<7]) == [255, 0, 0])
        let reconstructed = try #require(CameraFrameRenderer.image(from: frame))
        let second = try CameraFrameRenderer.frame(from: reconstructed)
        #expect(second.pixelWidth == 2 && second.pixelHeight == 1)
        #expect(Array(second.data.prefix(3)) == Array(frame.data.prefix(3)))
        #expect(Array(second.data[4..<7]) == Array(frame.data[4..<7]))
    }

    @Test
    func rawFrameContractRejectsInvalidDimensionsAndMismatchedBytes() throws {
        for (width, height, count) in [(0, 1, 0), (-1, 1, 0), (961, 1, 3_844), (1, 961, 3_844), (2, 2, 15), (1, 1, 5)] {
            #expect(throws: CameraCaptureError.invalidFrame) {
                try CameraPreviewFrame(data: Data(repeating: 0, count: count), pixelWidth: width, pixelHeight: height)
            }
        }
        let largest = try CameraPreviewFrame(data: Data(repeating: 0, count: 960 * 960 * 4), pixelWidth: 960, pixelHeight: 960)
        #expect(largest.bytesPerRow == 3_840)
    }

    @Test
    func rasterizerRejectsImagesLargerThanThePreviewContract() throws {
        let source = try image(width: 961, height: 1, bytes: [UInt8](repeating: 100, count: 961 * 4))
        #expect(throws: CameraCaptureError.invalidFrame) { try CameraFrameRenderer.frame(from: source) }
    }

    private func image(width: Int, height: Int, bytes: [UInt8]) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
