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
        await withCheckedContinuation { continuation in
            NSColorSampler().show { color in
                guard let color, let converted = color.usingColorSpace(.sRGB) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: CommandlyColor(
                        red: converted.redComponent,
                        green: converted.greenComponent,
                        blue: converted.blueComponent,
                        alpha: converted.alphaComponent
                    )
                )
            }
        }
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
