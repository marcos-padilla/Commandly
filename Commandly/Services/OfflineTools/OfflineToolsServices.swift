import AppKit
import CoreServices
import Foundation
import Infrastructure

protocol DictionaryLookingUp: Sendable {
    func definition(for word: String) async -> String?
}

struct SystemDictionaryLookup: DictionaryLookingUp {
    nonisolated func definition(for word: String) async -> String? {
        // Dictionary Services exposes a synchronous lookup that may read dictionary data from
        // disk. Keep that work off the main actor so opening the application remains responsive.
        await Task.detached(priority: .userInitiated) {
            let query = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.isEmpty == false else { return nil }
            let length = (query as NSString).length
            return DCSCopyTextDefinition(nil, query as CFString, CFRange(location: 0, length: length))?
                .takeRetainedValue() as String?
        }.value
    }
}

@MainActor
protocol ColorSampling: AnyObject {
    func sample() async -> CommandlyColor?
}

@MainActor
final class SystemColorSampler: ColorSampling {
    func sample() async -> CommandlyColor? {
        let continuationGate = ColorSamplingContinuationGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuationGate.install(continuation)
                guard Task.isCancelled == false else {
                    continuationGate.resume(returning: nil)
                    return
                }
                NSColorSampler().show { color in
                    guard let color, let converted = color.usingColorSpace(.sRGB) else {
                        continuationGate.resume(returning: nil)
                        return
                    }
                    continuationGate.resume(
                        returning: CommandlyColor(
                            red: converted.redComponent,
                            green: converted.greenComponent,
                            blue: converted.blueComponent,
                            alpha: converted.alphaComponent
                        )
                    )
                }
            }
        } onCancel: {
            continuationGate.resume(returning: nil)
        }
    }
}

/// Bridges AppKit's callback and task cancellation into one continuation result.
///
/// `@unchecked Sendable` is safe here because every read and write of the
/// continuation and completion flag is serialized by `lock`. The winning path
/// removes the continuation while holding the lock and resumes it afterward,
/// so the AppKit callback and cancellation handler cannot resume it twice.
private nonisolated final class ColorSamplingContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CommandlyColor?, Never>?
    private var isCompleted = false

    func install(_ continuation: CheckedContinuation<CommandlyColor?, Never>) {
        let shouldResumeImmediately = lock.withLock {
            guard isCompleted == false else { return true }
            self.continuation = continuation
            return false
        }
        if shouldResumeImmediately {
            continuation.resume(returning: nil)
        }
    }

    func resume(returning color: CommandlyColor?) {
        let continuation = lock.withLock {
            guard isCompleted == false else {
                return Optional<CheckedContinuation<CommandlyColor?, Never>>.none
            }
            isCompleted = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: color)
    }
}

@MainActor
protocol FontCatalogProviding: AnyObject {
    var availableFamilies: [String] { get }
}

@MainActor
final class SystemFontCatalog: FontCatalogProviding {
    var availableFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

@MainActor
struct OfflineToolsServices {
    let pasteboard: any PasteboardAccessing
    let dictionary: any DictionaryLookingUp
    let colorSampler: any ColorSampling
    let fontCatalog: any FontCatalogProviding
    let now: () -> Date

    init(
        pasteboard: any PasteboardAccessing,
        dictionary: any DictionaryLookingUp = SystemDictionaryLookup(),
        colorSampler: any ColorSampling = SystemColorSampler(),
        fontCatalog: any FontCatalogProviding = SystemFontCatalog(),
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.dictionary = dictionary
        self.colorSampler = colorSampler
        self.fontCatalog = fontCatalog
        self.now = now
    }
}
