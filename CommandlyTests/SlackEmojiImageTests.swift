import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

struct SlackEmojiImageTests {
    @Test func generatedStaticAndAnimatedImagesRetainTheirNativeTypesAndFrames() async throws {
        let generator = GeneratedSlackEmojiMedia(); let decoder = SlackEmojiImageDecoder()
        let png = try await generator.make(animated: false); let gif = try await generator.make(animated: true)
        let still = try await decoder.preview(png); let animated = try await decoder.preview(gif)
        #expect(still.info.typeIdentifier == UTType.png.identifier); #expect(still.animation == nil)
        #expect(animated.info.animated); #expect(animated.info.typeIdentifier == UTType.gif.identifier)
        #expect(animated.animation?.frames.count == 4); #expect(animated.image.width <= 360)
        await #expect(throws: SlackEmojiError.invalidImage) { try await decoder.inspect(Data("<svg>not an emoji</svg>".utf8)) }
        let longGIF = try await generator.make(animated: true, frameCount: 401, dimension: 10)
        #expect(try await decoder.inspect(longGIF).animated)
        await #expect(throws: SlackEmojiError.previewTooLarge) { try await decoder.preview(longGIF) }
    }
    @MainActor @Test func explicitNameAndImageCopiesStaySeparateAndCancelledCopyDoesNothing() async throws {
        let capture = SlackEmojiExportCapture(); let gif = try await GeneratedSlackEmojiMedia().make(animated: true)
        let exporter = NativeSlackEmojiExporter(writeName: { capture.names.append($0); return true }, writeImage: { capture.images.append(($0, $1)); return true }, chooseDestination: { _, _ in nil })
        try exporter.copyName("wave"); #expect(capture.names == [":wave:"]); #expect(capture.images.isEmpty)
        try await exporter.copyImage(gif); #expect(capture.images.count == 1)
        #expect(capture.images.first?.0 == gif); #expect(capture.images.first?.1 == UTType.gif.identifier)
        let copy = Task { try await exporter.copyImage(gif) }; copy.cancel()
        await #expect(throws: CancellationError.self) { try await copy.value }; #expect(capture.images.count == 1)
        #expect(try await exporter.saveImage(gif, name: "wave") == false)
    }
    @MainActor @Test func nativeSavePreservesBothOriginalFormatsAndReplacesOnlyChosenFile() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("commandly-slack-emoji-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let generator = GeneratedSlackEmojiMedia()
        for animated in [false, true] {
            let bytes = try await generator.make(animated: animated)
            let destination = parent.appendingPathComponent(animated ? "Chosen.gif" : "Chosen.png")
            try Data("Previous generated fixture".utf8).write(to: destination)
            let exporter = NativeSlackEmojiExporter(writeName: { _ in false }, writeImage: { _, _ in false }, chooseDestination: { _, _ in destination })
            #expect(try await exporter.saveImage(bytes, name: "fixture"))
            #expect(try Data(contentsOf: destination) == bytes)
            let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
            #expect(CGImageSourceGetCount(source) == (animated ? 4 : 1))
        }
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: parent.path)) == ["Chosen.gif", "Chosen.png"])
    }
}
@MainActor private final class SlackEmojiExportCapture { var names: [String] = []; var images: [(Data, String)] = [] }
