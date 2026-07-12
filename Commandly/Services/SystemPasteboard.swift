import Foundation
import AppKit
import Infrastructure

/// Writes/reads strings through the general pasteboard.
struct SystemPasteboard: PasteboardAccessing {
    func readString() async -> String? {
        NSPasteboard.general.string(forType: .string)
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
final class InMemoryPasteboard: PasteboardAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var files: [URL] = []

    init(initial: String? = nil) {
        self.value = initial
    }

    func readString() async -> String? {
        lock.withLock { value }
    }

    func writeString(_ string: String) async {
        lock.withLock { value = string }
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
