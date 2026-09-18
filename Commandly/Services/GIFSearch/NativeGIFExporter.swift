import AppKit
import Foundation
import Infrastructure
import UniformTypeIdentifiers

/// Native explicit export UI. The writer works off MainActor and receives one Save Panel URL grant.
@MainActor
struct NativeGIFExporter: GIFExporting {
    private let decoder: any GIFAnimationDecoding
    private let writer: NativeGIFFileWriter
    private let pasteboard: @MainActor @Sendable (Data) -> Bool
    private let chooseDestination: @MainActor @Sendable (String) async -> URL?
    init(decoder: any GIFAnimationDecoding = GIFAnimationDecoder(), writer: NativeGIFFileWriter = NativeGIFFileWriter(),
         pasteboard: @escaping @MainActor @Sendable (Data) -> Bool = { data in
             let item = NSPasteboardItem()
             guard item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier)) else { return false }
             NSPasteboard.general.clearContents(); return NSPasteboard.general.writeObjects([item])
         }, chooseDestination: @escaping @MainActor @Sendable (String) async -> URL? = { suggested in
             let panel = NSSavePanel(); panel.allowedContentTypes = [.gif]; panel.allowsOtherFileTypes = false
             panel.canCreateDirectories = true; panel.nameFieldStringValue = suggested
             let response = await withTaskCancellationHandler { await panel.begin() }
             onCancel: { Task { @MainActor in panel.cancel(nil) } }
             return response == .OK ? panel.url : nil
         }) {
        self.decoder = decoder; self.writer = writer; self.pasteboard = pasteboard; self.chooseDestination = chooseDestination
    }
    func copy(_ data: Data) async throws {
        try await decoder.validateOriginal(data); try Task.checkCancellation()
        guard pasteboard(data) else { throw GIFSearchError.copyFailed }
    }
    func save(_ data: Data, suggestedName: String) async throws -> Bool {
        try await decoder.validateOriginal(data); try Task.checkCancellation()
        guard let destination = await chooseDestination(suggestedName) else { return false }
        try Task.checkCancellation()
        guard destination.isFileURL, destination.pathExtension.lowercased() == "gif" else { throw GIFSearchError.exportFailed }
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        try await writer.write(data, to: destination)
        return true // A completed atomic commit remains successful if cancellation arrives afterward.
    }
}
