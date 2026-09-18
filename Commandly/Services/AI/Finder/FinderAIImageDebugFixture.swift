#if DEBUG
import AIKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Infrastructure
import SearchKit
import UniformTypeIdentifiers

/// Opt-in generated UI acceptance only. Construction performs no generation or filesystem access.
/// Opening Finder AI prepares one isolated generated folder; the normal tool/UI approval path owns
/// every conversion. It has no real bookmark store, provider, credentials, search index, or revealer.
@MainActor
struct FinderAIImageDebugFixture {
    nonisolated static let prompt = "Convert the generated image to a 320-pixel JPEG rotated clockwise."
    let services: FinderAIApplicationServices
    let files: FinderAIImageFixtureFiles
    let runtime: FinderAIImageFixtureRuntime

    init() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Commandly-Generated-Finder-Image-\(UUID().uuidString)", isDirectory: true)
        let files = FinderAIImageFixtureFiles(directory: directory)
        let runtime = FinderAIImageFixtureRuntime(files: files)
        let workspace = FinderAIWorkspaceService(
            folderAccessStore: InMemoryFolderAccessStore(), searchService: InMemoryFileSearchService(),
            fileRevealer: InMemoryFileRevealer(), directAuthorizedRoots: [directory],
            protectedUserHomeDirectory: directory.deletingLastPathComponent().appendingPathComponent("Commandly-Unused-Home-\(UUID().uuidString)"),
            protectedVolumeRoots: [], commandlyOwnedDataDirectories: [],
            imageConverter: NativeImageConversionService()
        )
        self.files = files
        self.runtime = runtime
        self.services = FinderAIApplicationServices(runtime: runtime, workspace: workspace,
            toolExecutor: FinderAIToolExecutor(workspace: workspace, approvalCoordinator: workspace))
    }
}

nonisolated enum FinderAIImageFixtureError: Error { case generationFailed, invalidTranscript }

/// Pixel generation and all generated-file work are confined to this actor, away from MainActor.
/// One UUID directory is retained for native inspection, never enumerated from prior runs or reused.
actor FinderAIImageFixtureFiles {
    nonisolated let directory: URL
    nonisolated var source: URL { directory.appendingPathComponent("generated-source.png") }
    nonisolated var output: URL { directory.appendingPathComponent("Output/generated-converted.jpg") }
    private var prepared = false

    init(directory: URL) { self.directory = directory }

    func prepare() throws {
        try Task.checkCancellation()
        guard !prepared else { return }
        let data = try Self.generatedPNG()
        // Exclusive fresh folder creation means a previous fixture or other file is never replaced.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("Output"),
                                                    withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try Task.checkCancellation()
            try data.write(to: source, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
            prepared = true
        } catch {
            // Only this call's freshly created UUID directory can reach this cleanup.
            try FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func generatedPNG() throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FinderAIImageFixtureError.generationFailed
        }
        context.setFillColor(red: 0.08, green: 0.13, blue: 0.23, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        context.setFillColor(red: 0.28, green: 0.75, blue: 0.74, alpha: 1)
        context.fillEllipse(in: CGRect(x: 460, y: 180, width: 120, height: 120))
        context.setFillColor(red: 0.94, green: 0.62, blue: 0.25, alpha: 1)
        context.fill(CGRect(x: 56, y: 72, width: 300, height: 24))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 30, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "GENERATED IMAGE", attributes: attributes))
        context.textPosition = CGPoint(x: 56, y: 160)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { throw FinderAIImageFixtureError.generationFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw FinderAIImageFixtureError.generationFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [
            kCGImagePropertyPNGDescription: "Commandly generated UI acceptance fixture"
        ]] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FinderAIImageFixtureError.generationFailed }
        return data as Data
    }
}
#endif
