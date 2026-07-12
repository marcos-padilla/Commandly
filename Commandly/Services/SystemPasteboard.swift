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
}

/// In-memory pasteboard for tests.
final class InMemoryPasteboard: PasteboardAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(initial: String? = nil) {
        self.value = initial
    }

    func readString() async -> String? {
        lock.withLock { value }
    }

    func writeString(_ string: String) async {
        lock.withLock { value = string }
    }

    var currentValue: String? {
        lock.withLock { value }
    }
}
