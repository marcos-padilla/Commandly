import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

struct NativeImageRecognitionServiceTests {
    @Test
    func accurateOCRReadsGeneratedTextWithoutUsingUserFiles() async throws {
        let context = try RecognitionImageFixture.context(width: 1_400, height: 400)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 90, nil)
        let string = NSAttributedString(string: "COMMANDLY 4821", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 80, y: 170)
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
        let source = try RecognitionImageFixture.source(try #require(context.makeImage()))
        let result = try await NativeImageRecognitionService().recognize(source, mode: .text)
        #expect(result.text.contains("COMMANDLY"))
        #expect(result.text.contains("4821"))
        #expect(result.qrPayloads.isEmpty)
        #expect(result.isTruncated == false)
    }

    @Test
    func QRPayloadsAreDecodedExactlyIncludingNewlinesAndOrientation() async throws {
        let service = NativeImageRecognitionService()
        for payload in ["https://example.invalid/image-tools", "Line 1\nLine 2"] {
            let image = try RecognitionImageFixture.qr(payload)
            let source = try RecognitionImageFixture.source(image, orientation: 6)
            let original = source.data
            let result = try await service.recognize(source, mode: .qr)
            #expect(result.qrPayloads == [payload])
            #expect(result.text.isEmpty)
            #expect(source.data == original)
        }
    }

    @Test
    func blankImagesReturnSuccessfulEmptyResults() async throws {
        let context = try RecognitionImageFixture.context(width: 500, height: 300)
        let source = try RecognitionImageFixture.source(try #require(context.makeImage()))
        let service = NativeImageRecognitionService()
        let text = try await service.recognize(source, mode: .text)
        let qr = try await service.recognize(source, mode: .qr)
        #expect(text.text.isEmpty)
        #expect(qr.qrPayloads.isEmpty && qr.nonTextQRCodeCount == 0)
    }

    @Test
    func recognitionRevalidatesBytesAndHonorsPreCancellation() async throws {
        let invalid = ImageConversionSource(data: Data("invalid image".utf8), previewPNGData: Data(),
                                            filename: "fixture.png", pixelWidth: 1, pixelHeight: 1)
        let service = NativeImageRecognitionService()
        await #expect(throws: ImageConversionError.invalidImage) { try await service.recognize(invalid, mode: .text) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.recognize(invalid, mode: .qr)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func outputBoundsPreserveGraphemesAndNeverTruncateQRPayloadsIntoLinks() {
        let text = ImageRecognitionOutput.text([String(repeating: "a", count: 63_998), "👩🏽‍🚀x"])
        #expect(text.text.count == 64_000)
        #expect(text.text.hasSuffix("\n👩🏽‍🚀"))
        #expect(text.isTruncated)
        let payload = " https://example.invalid/a\n"
        let qr = ImageRecognitionOutput.qr([payload, payload, nil, String(repeating: "x", count: 4_097)])
        #expect(qr.qrPayloads == [payload])
        #expect(qr.nonTextQRCodeCount == 1)
        #expect(qr.isTruncated)
        let many = ImageRecognitionOutput.qr((0..<33).map { "code-\($0)" })
        #expect(many.qrPayloads.count == 32 && many.isTruncated)
        let long = ImageRecognitionOutput.qr((0..<32).map { "\($0)-" + String(repeating: "x", count: 4_000) })
        #expect(long.qrPayloads.joined().count <= 64_000 && long.isTruncated)
    }
}

private enum RecognitionImageFixture {
    static func context(width: Int, height: Int) throws -> CGContext {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    static func source(_ image: CGImage, orientation: Int = 1) throws -> ImageConversionSource {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return ImageConversionSource(data: data as Data, previewPNGData: Data(), filename: "generated.tiff",
                                     pixelWidth: image.width, pixelHeight: image.height)
    }

    static func qr(_ payload: String) throws -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        let code = try #require(filter.outputImage)
        let background = CIImage(color: CIColor.white).cropped(to: code.extent.insetBy(dx: -4, dy: -4))
        let padded = code.composited(over: background).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return try #require(CIContext().createCGImage(padded, from: padded.extent))
    }
}
