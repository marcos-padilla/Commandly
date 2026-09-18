import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import SearchKit
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import Commandly

nonisolated struct FinderAIImageTestFiles: Sendable {
    let base: URL
    let root: URL
    let destination: URL
    let source: URL
    let sourceData: Data
    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("Commandly-AIImage-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Authorized", isDirectory: true)
        destination = root.appendingPathComponent("Output", isDirectory: true)
        source = root.appendingPathComponent("source.png")
        sourceData = try Self.png(privateMetadata: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try sourceData.write(to: source)
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
    func service(converter: any ImageDataConverting = NativeImageConversionService(), now: @escaping @Sendable () -> Date = { Date() }) async -> FinderAIWorkspaceService {
        let store = await MainActor.run { InMemoryFolderAccessStore() }
        return FinderAIWorkspaceService(folderAccessStore: store, searchService: InMemoryFileSearchService(),
            fileRevealer: FinderAIImageNoOpRevealer(), directAuthorizedRoots: [root],
            protectedUserHomeDirectory: base.appendingPathComponent("OtherHome"), protectedVolumeRoots: [], commandlyOwnedDataDirectories: [],
            imageConverter: converter, now: now)
    }
    func handles(_ service: FinderAIWorkspaceService) async throws -> FinderAIImageHandles {
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        return FinderAIImageHandles(session: session, root: root.id,
            source: try #require(page.items.first { $0.displayName == "source.png" }).id,
            destination: try #require(page.items.first { $0.displayName == "Output" }).id)
    }
    static func png(privateMetadata: Bool = false) throws -> Data {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.25, green: 0.65, blue: 0.9, alpha: 0.5)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let output = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if privateMetadata {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: "PRIVATE GENERATED SOURCE DESCRIPTION"]
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "PRIVATE GENERATED EXIF"]
            properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 12.34, kCGImagePropertyGPSLatitudeRef: "N"]
        }
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(output))
        return data as Data
    }
}
nonisolated struct FinderAIImageHandles: Sendable {
    let session: FinderAISessionID
    let root: FinderAIRootID
    let source: FinderAIItemID
    let destination: FinderAIItemID
    func request(name: String = "converted.png", options: ImageConversionOptions = .init()) -> FinderAIMutationRequest {
        .init(operations: [.convertImage(.init(source: source, destination: .item(destination), outputName: name, options: options))])
    }
}
nonisolated private struct FinderAIImageNoOpRevealer: FileRevealing { func revealInFinder(urls: [URL]) async throws {} }

actor FinderAIImageGatedConverter: ImageDataConverting {
    let formats: [ImageConversionFormat]
    let result: ImageConversionResult
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    init(formats: [ImageConversionFormat] = [.png]) throws {
        self.formats = formats
        result = ImageConversionResult(data: try FinderAIImageTestFiles.png(), previewPNGData: Data(), format: .png, pixelWidth: 4, pixelHeight: 2)
    }
    func supportedFormats() -> [ImageConversionFormat] { formats }
    func convertImageData(_ data: Data, options: ImageConversionOptions) async throws -> ImageConversionResult {
        calls += 1
        await withCheckedContinuation { pending in
            continuation = pending
            waiters.values.forEach { $0.resume() }; waiters.removeAll()
        }
        // Deliberately ignores cancellation: workspace guards must still suppress a stale write.
        return result
    }
    func waitForConversion() async throws {
        try Task.checkCancellation()
        if calls > 0 { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }
    private func cancelWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
    func release() { continuation?.resume(); continuation = nil }
}

nonisolated final class FinderAIImageClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 10_000))
    func now() -> Date { date.withLock { $0 } }
    func advance() { date.withLock { $0 = $0.addingTimeInterval(121) } }
}
