import CommandKit
import Foundation

/// A cached command catalog shares the same store as the custom-layout editor.
@MainActor final class WindowLayoutCommandCatalog: CustomWindowLayoutStoring {
    private let store: any CustomWindowLayoutStoring
    private(set) var customLayouts: [CustomWindowLayout] = []
    private var loadingError: (any Error)?
    var onCatalogChange: (() throws -> Void)?
    init(store: any CustomWindowLayoutStoring) {
        self.store = store
        do { customLayouts = try Self.validated(store.load()) }
        catch { loadingError = error }
    }
    var presets: [WindowLayoutPreset] {
        WindowLayoutCatalog.presets + customLayouts.map {
            .init(id: "custom." + $0.id.uuidString.lowercased(), title: $0.title, family: .featured, rect: $0.rect)
        }
    }
    static func toolID(_ preset: WindowLayoutPreset) -> CommandID { .init(rawValue: "windows.layouts.apply." + preset.id) }
    func preset(toolID: CommandID) -> WindowLayoutPreset? { presets.first { Self.toolID($0) == toolID } }
    func load() throws -> [CustomWindowLayout] {
        if let loadingError { throw loadingError }
        return customLayouts
    }
    func save(_ layout: CustomWindowLayout) throws {
        _ = try Self.validated(customLayouts.filter { $0.id != layout.id } + [layout])
        try store.save(layout); try refresh()
    }
    func delete(id: UUID) throws { try store.delete(id: id); try refresh() }
    func refresh() throws {
        do { customLayouts = try Self.validated(store.load()); loadingError = nil }
        catch { loadingError = error; throw error }
        try onCatalogChange?()
    }
    private static func validated(_ values: [CustomWindowLayout]) throws -> [CustomWindowLayout] {
        guard values.count <= 256, Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ $0.rect.isValid && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.title.utf8.count <= 160 && !$0.title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else {
            throw CustomWindowLayoutStoreError.unreadable
        }
        return values
    }
}
