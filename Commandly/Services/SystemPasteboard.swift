import Foundation
import AppKit
import Infrastructure

/// Writes/reads strings through the general pasteboard.
struct SystemPasteboard: PasteboardAccessing {
    func readString() async -> String? {
        await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
    }

    func readFileURLs() async -> [URL] {
        await MainActor.run {
            NativePasteboardContentReader.readFileURLs(from: .general)
        }
    }

    func readContent() async -> PasteboardContent? {
        await MainActor.run {
            NativePasteboardContentReader.read(from: .general)
        }
    }

    func writeString(_ string: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }

    func writeFileURLs(_ urls: [URL]) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
    }
}

/// In-memory pasteboard for tests.
///
/// Every mutable value is protected by `lock`; the unchecked conformance only bridges this
/// lock-based implementation to the protocol's `Sendable` requirement.
final class InMemoryPasteboard: PasteboardAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var files: [URL] = []
    private var image: PasteboardImageContent?

    init(
        initial: String? = nil,
        initialFileURLs: [URL] = [],
        initialImage: PasteboardImageContent? = nil
    ) {
        self.value = initial
        self.files = initialFileURLs
        self.image = initialImage
    }

    func readString() async -> String? {
        lock.withLock { value }
    }

    func writeString(_ string: String) async {
        lock.withLock {
            value = string
            files = []
            image = nil
        }
    }

    func readFileURLs() async -> [URL] {
        lock.withLock { files }
    }

    func readContent() async -> PasteboardContent? {
        lock.withLock {
            if files.isEmpty == false {
                return .fileURLs(files)
            }
            if let image {
                return .image(image)
            }
            guard let value,
                  value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return .text(value)
        }
    }

    func writeFileURLs(_ urls: [URL]) async {
        lock.withLock {
            files = urls
            value = nil
            image = nil
        }
    }

    var currentValue: String? {
        lock.withLock { value }
    }

    var currentFileURLs: [URL] {
        lock.withLock { files }
    }
}

/// Shared one-shot native pasteboard reader used by Shelf and Clipboard History.
@MainActor
enum NativePasteboardContentReader {
    static func read(from pasteboard: NSPasteboard) -> PasteboardContent? {
        let fileURLs = readFileURLs(from: pasteboard)
        if fileURLs.isEmpty == false {
            return .fileURLs(fileURLs)
        }
        if let type = pasteboard.availableType(from: [.png, .tiff]),
           let data = pasteboard.data(forType: type) {
            let typeIdentifier = type == .png ? "public.png" : "public.tiff"
            return .image(
                PasteboardImageContent(data: data, typeIdentifier: typeIdentifier)
            )
        }
        guard let string = pasteboard.string(forType: .string),
              string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return .text(string)
    }

    static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        return objects.compactMap { object in
            guard let url = object as? URL, url.isFileURL else { return nil }
            return url
        }
    }
}
