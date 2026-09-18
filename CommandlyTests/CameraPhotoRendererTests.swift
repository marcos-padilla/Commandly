import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

@Suite("Camera photo rendering")
struct CameraPhotoRendererTests {
    @Test
    func horizontalMirrorReversesPixelsExactlyOnce() throws {
        let source = try CameraImageFixture.encode(width: 12, height: 8)
        let regular = try CameraPhotoRenderer.render(source, mirrored: false)
        let mirrored = try CameraPhotoRenderer.render(source, mirrored: true)
        let regularImage = try CameraImageFixture.decode(regular.pngData)
        let mirroredImage = try CameraImageFixture.decode(mirrored.pngData)
        let originalBytes = try CameraImageFixture.rgba(regularImage)
        let mirroredBytes = try CameraImageFixture.rgba(mirroredImage)

        for row in 0..<regularImage.height {
            for column in 0..<regularImage.width {
                let original = (row * regularImage.width + column) * 4
                let reflected = (row * mirroredImage.width + mirroredImage.width - column - 1) * 4
                #expect(originalBytes[original..<original + 4] == mirroredBytes[reflected..<reflected + 4])
            }
        }
        #expect(try CameraImageFixture.rgba(CameraImageFixture.decode(mirrored.previewPNGData)) == mirroredBytes)
    }

    @Test
    func orientationIsNormalizedBeforeRendering() throws {
        let source = try CameraImageFixture.encode(
            width: 120, height: 80, type: .tiff,
            metadata: [kCGImagePropertyOrientation: 6]
        )
        let photo = try CameraPhotoRenderer.render(source, mirrored: false)
        let image = try CameraImageFixture.decode(photo.pngData)
        let properties = try CameraImageFixture.properties(photo.pngData)

        #expect(photo.pixelWidth == 80 && photo.pixelHeight == 120)
        #expect(image.width == 80 && image.height == 120)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test
    func fullPhotoAndPreviewHaveIndependentAspectPreservingBounds() throws {
        let source = try CameraImageFixture.encode(width: 5_000, height: 1_000)
        let photo = try CameraPhotoRenderer.render(source, mirrored: false)
        let image = try CameraImageFixture.decode(photo.pngData)
        let preview = try CameraImageFixture.decode(photo.previewPNGData)

        #expect(image.width == 4_096)
        #expect(abs(Double(image.height) - Double(image.width) / 5) <= 1)
        #expect(photo.pixelWidth == image.width && photo.pixelHeight == image.height)
        #expect(preview.width == 960)
        #expect(abs(Double(preview.height) - Double(preview.width) / 5) <= 1)
    }

    @Test
    func smallPhotoAndPreviewAreNotUpscaled() throws {
        let source = try CameraImageFixture.encode(width: 64, height: 32)
        let photo = try CameraPhotoRenderer.render(source, mirrored: false)
        let preview = try CameraImageFixture.decode(photo.previewPNGData)

        #expect(photo.pixelWidth == 64 && photo.pixelHeight == 32)
        #expect(preview.width == 64 && preview.height == 32)
    }

    @Test
    func exportedPhotoAndPreviewDropSourceLocationAndComments() throws {
        let source = try CameraImageFixture.encode(
            width: 32, height: 16, type: .tiff,
            metadata: [
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 12.3,
                    kCGImagePropertyGPSLatitudeRef: "N"
                ],
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFImageDescription: "private camera fixture"
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifUserComment: "private capture comment"
                ]
            ]
        )
        let sourceProperties = try CameraImageFixture.properties(source)
        #expect(sourceProperties[kCGImagePropertyGPSDictionary] != nil)
        let sourceExif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(sourceExif?[kCGImagePropertyExifUserComment] as? String == "private capture comment")
        let photo = try CameraPhotoRenderer.render(source, mirrored: true)

        for encoded in [photo.pngData, photo.previewPNGData] {
            let properties = try CameraImageFixture.properties(encoded)
            #expect(properties[kCGImagePropertyGPSDictionary] == nil)
            // ImageIO may synthesize technical EXIF for fresh sRGB PNG pixels. It must not
            // carry camera/source fields such as user comments, time, maker, or location.
            let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any] ?? [:]
            let technicalKeys: Set<String> = [
                kCGImagePropertyExifColorSpace as String,
                kCGImagePropertyExifPixelXDimension as String,
                kCGImagePropertyExifPixelYDimension as String
            ]
            #expect(Set(exif.keys).isSubset(of: technicalKeys))
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            #expect(tiff?[kCGImagePropertyTIFFImageDescription] == nil)
            let imageSource = try #require(CGImageSourceCreateWithData(encoded as CFData, nil))
            #expect(CGImageSourceGetType(imageSource) as String? == UTType.png.identifier)
        }
    }

    @Test
    func corruptedAndAnimatedImagesAreRejected() throws {
        for data in [Data(), Data("not a camera image".utf8)] {
            #expect(throws: ImageConversionError.invalidImage) {
                try CameraPhotoRenderer.render(data, mirrored: false)
            }
        }
        let animated = try CameraImageFixture.encode(width: 4, height: 4, type: .gif, frameCount: 2)
        #expect(throws: ImageConversionError.animatedImageUnsupported) {
            try CameraPhotoRenderer.render(animated, mirrored: false)
        }
    }

    @Test
    func oversizedBytesAndSourceDimensionsAreRejected() throws {
        let oversized = Data(repeating: 0, count: 64 * 1_024 * 1_024 + 1)
        #expect(throws: ImageConversionError.inputTooLarge) {
            try CameraPhotoRenderer.render(oversized, mirrored: false)
        }
        let wide = try CameraImageFixture.encode(width: 16_385, height: 1)
        #expect(throws: ImageConversionError.inputTooLarge) {
            try CameraPhotoRenderer.render(wide, mirrored: false)
        }
    }

    @Test
    func cancelledRenderingDoesNotAttemptDecoding() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CameraPhotoRenderer.render(Data(), mirrored: false)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

private enum CameraImageFixture {
    static func encode(
        width: Int, height: Int, type: UTType = .png, frameCount: Int = 1,
        metadata: [CFString: Any] = [:]
    ) throws -> Data {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width / 2), height: height))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width / 4), height: max(1, height / 2)))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, type.identifier as CFString, frameCount, nil
        ))
        for _ in 0..<frameCount { CGImageDestinationAddImage(destination, image, metadata as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
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
