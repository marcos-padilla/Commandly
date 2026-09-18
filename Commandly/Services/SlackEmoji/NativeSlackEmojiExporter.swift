import AppKit
import Foundation
import Infrastructure
import UniformTypeIdentifiers

/// Original bytes are preserved. The existing coordinated file writer needs only an exact Save grant.
@MainActor
struct NativeSlackEmojiExporter: SlackEmojiExporting {
    private let decoder: any SlackEmojiImageDecoding
    private let writer: NativeGIFFileWriter
    private let writeName: @MainActor @Sendable (String) -> Bool
    private let writeImage: @MainActor @Sendable (Data, String) -> Bool
    private let chooseDestination: @MainActor @Sendable (String, String) async -> URL?
    init(decoder: any SlackEmojiImageDecoding = SlackEmojiImageDecoder(), writer: NativeGIFFileWriter = NativeGIFFileWriter(),
         writeName: @escaping @MainActor @Sendable (String) -> Bool = { value in
             NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(value, forType: .string)
         }, writeImage: @escaping @MainActor @Sendable (Data, String) -> Bool = { data, type in
             let item = NSPasteboardItem(); guard item.setData(data, forType: .init(type)) else { return false }
             NSPasteboard.general.clearContents(); return NSPasteboard.general.writeObjects([item])
         }, chooseDestination: @escaping @MainActor @Sendable (String, String) async -> URL? = { name, type in
             guard let contentType = UTType(type) else { return nil }
             let panel = NSSavePanel(); panel.allowedContentTypes = [contentType]; panel.allowsOtherFileTypes = false
             panel.canCreateDirectories = true; panel.nameFieldStringValue = name
             let response = await withTaskCancellationHandler { await panel.begin() }
             onCancel: { Task { @MainActor in panel.cancel(nil) } }
             return response == .OK ? panel.url : nil
         }) {
        self.decoder = decoder; self.writer = writer; self.writeName = writeName; self.writeImage = writeImage; self.chooseDestination = chooseDestination
    }
    func copyName(_ name: String) throws {
        try Task.checkCancellation(); guard SlackEmojiCatalogParser.validName(name) else { throw SlackEmojiError.copyFailed }
        guard writeName(":" + name + ":") else { throw SlackEmojiError.copyFailed }
    }
    func copyImage(_ data: Data) async throws {
        let info = try await decoder.inspect(data); try Task.checkCancellation()
        guard writeImage(data, info.typeIdentifier) else { throw SlackEmojiError.copyFailed }
    }
    func saveImage(_ data: Data, name: String) async throws -> Bool {
        let info = try await decoder.inspect(data); try Task.checkCancellation()
        let safeName = SlackEmojiCatalogParser.validName(name) ? name : "Slack emoji"
        guard let destination = await chooseDestination(safeName + "." + info.fileExtension, info.typeIdentifier) else { return false }
        try Task.checkCancellation()
        guard destination.isFileURL, UTType(filenameExtension: destination.pathExtension)?.identifier == info.typeIdentifier else { throw SlackEmojiError.exportFailed }
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        do { try await writer.write(data, to: destination); return true }
        catch is CancellationError { throw CancellationError() }
        catch GIFSearchError.exportCleanupFailed { throw SlackEmojiError.exportCleanupFailed }
        catch { throw SlackEmojiError.exportFailed }
    }
}
