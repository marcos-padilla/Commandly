import Foundation
import AppKit
import Infrastructure

/// Writes/reads strings through the general pasteboard.
struct SystemPasteboard: PasteboardAccessing {
    func readString() async -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func readFileURLs() async -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        return objects.compactMap { object in
            guard let url = object as? URL, url.isFileURL else { return nil }
            return url
        }
    }

    func writeString(_ string: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func writeFileURLs(_ urls: [URL]) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
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

    init(initial: String? = nil, initialFileURLs: [URL] = []) {
        self.value = initial
        self.files = initialFileURLs
    }

    func readString() async -> String? {
        lock.withLock { value }
    }

    func writeString(_ string: String) async {
        lock.withLock { value = string }
    }

    func readFileURLs() async -> [URL] {
        lock.withLock { files }
    }

    func writeFileURLs(_ urls: [URL]) async {
        lock.withLock { files = urls }
    }

    var currentValue: String? {
        lock.withLock { value }
    }

    var currentFileURLs: [URL] {
        lock.withLock { files }
    }
}
