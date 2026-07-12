import AppKit
import Foundation
import Observation

/// Kind of clipboard payload we keep in history.
enum ClipboardContentType: String, CaseIterable, Identifiable, Sendable {
    case text
    case image
    case fileURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .fileURL: return "File"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .fileURL: return "doc"
        }
    }
}

/// One captured clipboard entry. Contents must never be logged.
struct ClipboardHistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let contentType: ClipboardContentType
    let preview: String
    let text: String?
    let imageTIFFData: Data?
    let fileURLs: [URL]
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    /// OCR / PDF / file body indexed at capture time. Never logged.
    var searchableText: String?
    /// Vision classification labels (e.g. Flower). Indexed at capture time.
    var classificationLabels: [String]
    var enrichmentStatus: ClipboardEnrichmentStatus

    init(
        id: UUID,
        createdAt: Date,
        contentType: ClipboardContentType,
        preview: String,
        text: String?,
        imageTIFFData: Data?,
        fileURLs: [URL],
        sourceAppName: String?,
        sourceBundleIdentifier: String?,
        searchableText: String? = nil,
        classificationLabels: [String] = [],
        enrichmentStatus: ClipboardEnrichmentStatus = .notNeeded
    ) {
        self.id = id
        self.createdAt = createdAt
        self.contentType = contentType
        self.preview = preview
        self.text = text
        self.imageTIFFData = imageTIFFData
        self.fileURLs = fileURLs
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.searchableText = searchableText
        self.classificationLabels = classificationLabels
        self.enrichmentStatus = enrichmentStatus
    }

    var characterCount: Int {
        text?.count ?? 0
    }

    var wordCount: Int {
        guard let text, text.isEmpty == false else { return 0 }
        return text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// First file URL that looks like a raster/image file, if any.
    var firstImageFileURL: URL? {
        fileURLs.first { ClipboardImageFile.isImageFileURL($0) }
    }
}

/// Helpers for recognizing image paths among clipboard file URLs.
enum ClipboardImageFile {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "ico"
    ]

    static func isImageFileURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }
}

/// In-memory clipboard history with pasteboard polling.
///
/// Monitoring is intentionally headless: pasteboard polls must never activate the
/// app, open windows, or raise UI. Presentation is owned solely by explicit open
/// paths (launcher hotkey / Open Commandly).
///
/// Image/file entries are enriched once at capture time (Vision OCR, labels, PDF /
/// text extraction). Search only matches cached fields — never re-runs Vision while typing.
///
/// Never logs pasteboard contents. `@unchecked Sendable` is not used — this type is `@MainActor`.
@Observable
@MainActor
final class ClipboardHistoryStore {
    private(set) var entries: [ClipboardHistoryEntry] = []
    private let maxEntries: Int
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    /// When set, `poll` skips recording while `changeCount <=` this value.
    /// Used so Commandly's own "copy again" write-backs do not create history entries.
    private var suppressRecordingThroughChangeCount: Int?
    private var pollTask: Task<Void, Never>?
    private let dateProvider: () -> Date
    private let uuidProvider: () -> UUID
    private let enrichmentCoordinator: ClipboardEnrichmentCoordinator

    init(
        maxEntries: Int = 200,
        pasteboard: NSPasteboard = .general,
        dateProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init,
        enricher: any ClipboardContentEnriching = NoOpClipboardContentEnricher()
    ) {
        self.maxEntries = maxEntries
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.dateProvider = dateProvider
        self.uuidProvider = uuidProvider
        self.enrichmentCoordinator = ClipboardEnrichmentCoordinator(enricher: enricher)
        self.enrichmentCoordinator.attach(store: self)
    }

    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while let self, Task.isCancelled == false {
                self.poll()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        // Self-write suppression: ignore pasteboard changes through the changeCount
        // produced by `copyToPasteboard`. Also covers races where poll sampled an
        // older changeCount while a write-back was in flight.
        if let ceiling = suppressRecordingThroughChangeCount {
            lastChangeCount = changeCount
            if changeCount <= ceiling {
                if changeCount == ceiling {
                    suppressRecordingThroughChangeCount = nil
                }
                return
            }
            suppressRecordingThroughChangeCount = nil
        } else {
            lastChangeCount = changeCount
        }

        guard let entry = captureCurrentPasteboard() else { return }
        // Avoid duplicating the same text/file payload back-to-back.
        if let first = entries.first, first.preview == entry.preview, first.contentType == entry.contentType {
            return
        }
        insertCaptured(entry)
    }

    func entry(id: UUID) -> ClipboardHistoryEntry? {
        entries.first { $0.id == id }
    }

    /// Writes `entry` back to the pasteboard without appending a new history item.
    ///
    /// Suppression begins before mutation so an in-flight `poll` cannot record the
    /// write-back. Contents are never logged.
    func copyToPasteboard(_ entry: ClipboardHistoryEntry) {
        // Hold an open ceiling until we know the final changeCount after writing.
        suppressRecordingThroughChangeCount = Int.max

        pasteboard.clearContents()
        switch entry.contentType {
        case .text:
            pasteboard.setString(entry.text ?? entry.preview, forType: .string)
        case .image:
            if let data = entry.imageTIFFData {
                pasteboard.setData(data, forType: .tiff)
            }
        case .fileURL:
            pasteboard.writeObjects(entry.fileURLs as [NSURL])
        }

        let writtenChangeCount = pasteboard.changeCount
        lastChangeCount = writtenChangeCount
        suppressRecordingThroughChangeCount = writtenChangeCount
    }

    func delete(id: UUID) {
        enrichmentCoordinator.cancel(id: id)
        entries.removeAll { $0.id == id }
    }

    func clear() {
        enrichmentCoordinator.cancelAll()
        entries.removeAll()
    }

    /// Applies capture-time enrichment to a live entry. Ignores unknown IDs.
    func applyEnrichment(id: UUID, enrichment: ClipboardEnrichment) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].searchableText = enrichment.searchableText
        entries[index].classificationLabels = enrichment.classificationLabels
        entries[index].enrichmentStatus = enrichment.status
    }

    /// Seed helper for tests — does not touch the real pasteboard or enqueue enrichment.
    func replaceEntriesForTesting(_ entries: [ClipboardHistoryEntry]) {
        enrichmentCoordinator.cancelAll()
        self.entries = entries
    }

    /// Test helper: enqueue enrichment for an existing entry.
    func enqueueEnrichmentForTesting(_ entry: ClipboardHistoryEntry) {
        enrichmentCoordinator.enqueue(entry)
    }

    private func insertCaptured(_ entry: ClipboardHistoryEntry) {
        var stored = entry
        switch stored.contentType {
        case .text:
            stored.enrichmentStatus = .notNeeded
        case .image, .fileURL:
            stored.enrichmentStatus = .pending
        }
        entries.insert(stored, at: 0)
        if entries.count > maxEntries {
            let removed = entries.suffix(from: maxEntries)
            for stale in removed {
                enrichmentCoordinator.cancel(id: stale.id)
            }
            entries = Array(entries.prefix(maxEntries))
        }
        if stored.enrichmentStatus == .pending {
            enrichmentCoordinator.enqueue(stored)
        }
    }

    private func captureCurrentPasteboard() -> ClipboardHistoryEntry? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let sourceName = frontApp?.localizedName
        let sourceBundle = frontApp?.bundleIdentifier

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.isEmpty == false,
           urls.contains(where: \.isFileURL)
        {
            let fileURLs = urls.filter(\.isFileURL)
            let preview = fileURLs.map(\.lastPathComponent).joined(separator: ", ")
            return ClipboardHistoryEntry(
                id: uuidProvider(),
                createdAt: dateProvider(),
                contentType: .fileURL,
                preview: preview.isEmpty ? "File" : preview,
                text: nil,
                imageTIFFData: nil,
                fileURLs: fileURLs,
                sourceAppName: sourceName,
                sourceBundleIdentifier: sourceBundle,
                enrichmentStatus: .pending
            )
        }

        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            return ClipboardHistoryEntry(
                id: uuidProvider(),
                createdAt: dateProvider(),
                contentType: .image,
                preview: "Image",
                text: nil,
                imageTIFFData: imageData,
                fileURLs: [],
                sourceAppName: sourceName,
                sourceBundleIdentifier: sourceBundle,
                enrichmentStatus: .pending
            )
        }

        if let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           string.isEmpty == false
        {
            let preview = string
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = preview.count > 120 ? String(preview.prefix(117)) + "…" : preview
            return ClipboardHistoryEntry(
                id: uuidProvider(),
                createdAt: dateProvider(),
                contentType: .text,
                preview: clipped,
                text: string,
                imageTIFFData: nil,
                fileURLs: [],
                sourceAppName: sourceName,
                sourceBundleIdentifier: sourceBundle,
                enrichmentStatus: .notNeeded
            )
        }

        return nil
    }
}
