import Foundation

struct NormalizedWindowRect: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1.000_001 && y + height <= 1.000_001
    }
}

struct WindowLayoutPreset: Identifiable, Equatable, Hashable, Sendable {
    enum Family: String, CaseIterable, Sendable {
        case featured
        case halves
        case thirds
        case quarters
        case grid

        var title: String { rawValue.capitalized }
    }

    let id: String
    let title: String
    let family: Family
    let rect: NormalizedWindowRect
}

enum WindowLayoutCatalog {
    static let presets: [WindowLayoutPreset] = {
        var values: [WindowLayoutPreset] = [
            preset("maximize", "Maximize", .featured, 0, 0, 1, 1),
            preset("center-large", "Center Large", .featured, 0.1, 0.1, 0.8, 0.8),
            preset("center-medium", "Center Medium", .featured, 0.2, 0.15, 0.6, 0.7),
            preset("left-half", "Left Half", .halves, 0, 0, 0.5, 1),
            preset("right-half", "Right Half", .halves, 0.5, 0, 0.5, 1),
            preset("top-half", "Top Half", .halves, 0, 0, 1, 0.5),
            preset("bottom-half", "Bottom Half", .halves, 0, 0.5, 1, 0.5),
        ]

        for column in 0..<3 {
            values.append(
                preset(
                    "vertical-third-\(column)",
                    ["Left Third", "Center Third", "Right Third"][column],
                    .thirds,
                    Double(column) / 3,
                    0,
                    1.0 / 3,
                    1
                )
            )
        }
        for row in 0..<3 {
            values.append(
                preset(
                    "horizontal-third-\(row)",
                    ["Top Third", "Middle Third", "Bottom Third"][row],
                    .thirds,
                    0,
                    Double(row) / 3,
                    1,
                    1.0 / 3
                )
            )
        }
        values += [
            preset("left-two-thirds", "Left Two Thirds", .thirds, 0, 0, 2.0 / 3, 1),
            preset("right-two-thirds", "Right Two Thirds", .thirds, 1.0 / 3, 0, 2.0 / 3, 1),
            preset("top-two-thirds", "Top Two Thirds", .thirds, 0, 0, 1, 2.0 / 3),
            preset("bottom-two-thirds", "Bottom Two Thirds", .thirds, 0, 1.0 / 3, 1, 2.0 / 3),
        ]

        for row in 0..<2 {
            for column in 0..<2 {
                values.append(
                    preset(
                        "quarter-\(row)-\(column)",
                        "\(row == 0 ? "Top" : "Bottom") \(column == 0 ? "Left" : "Right") Quarter",
                        .quarters,
                        Double(column) / 2,
                        Double(row) / 2,
                        0.5,
                        0.5
                    )
                )
            }
        }

        for row in 0..<3 {
            for column in 0..<3 {
                values.append(
                    preset(
                        "grid-3-\(row)-\(column)",
                        "3×3 Cell \(row * 3 + column + 1)",
                        .grid,
                        Double(column) / 3,
                        Double(row) / 3,
                        1.0 / 3,
                        1.0 / 3
                    )
                )
            }
        }
        for row in 0..<3 {
            for column in 0..<2 {
                values.append(
                    preset(
                        "grid-3-wide-\(row)-\(column)",
                        "3×3 Wide \(row * 2 + column + 1)",
                        .grid,
                        Double(column) / 3,
                        Double(row) / 3,
                        2.0 / 3,
                        1.0 / 3
                    )
                )
            }
        }
        for column in 0..<3 {
            for row in 0..<2 {
                values.append(
                    preset(
                        "grid-3-tall-\(row)-\(column)",
                        "3×3 Tall \(column * 2 + row + 1)",
                        .grid,
                        Double(column) / 3,
                        Double(row) / 3,
                        1.0 / 3,
                        2.0 / 3
                    )
                )
            }
        }
        for row in 0..<4 {
            for column in 0..<4 {
                values.append(
                    preset(
                        "grid-4-\(row)-\(column)",
                        "4×4 Cell \(row * 4 + column + 1)",
                        .grid,
                        Double(column) / 4,
                        Double(row) / 4,
                        0.25,
                        0.25
                    )
                )
            }
        }
        precondition(values.count == 58)
        return values
    }()

    private static func preset(
        _ id: String,
        _ title: String,
        _ family: WindowLayoutPreset.Family,
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double
    ) -> WindowLayoutPreset {
        WindowLayoutPreset(
            id: id,
            title: title,
            family: family,
            rect: NormalizedWindowRect(x: x, y: y, width: width, height: height)
        )
    }
}

struct CustomWindowLayout: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var rect: NormalizedWindowRect
}

enum CustomWindowLayoutStoreError: LocalizedError, Equatable {
    case unreadable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Custom layouts could not be read. The saved data may be damaged."
        case .saveFailed:
            return "The custom layout could not be saved."
        }
    }
}

@MainActor
protocol CustomWindowLayoutStoring: AnyObject {
    func load() throws -> [CustomWindowLayout]
    func save(_ layout: CustomWindowLayout) throws
    func delete(id: UUID) throws
}

@MainActor
final class UserDefaultsCustomWindowLayoutStore: CustomWindowLayoutStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "window-layouts.custom.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> [CustomWindowLayout] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([CustomWindowLayout].self, from: data)
        } catch {
            throw CustomWindowLayoutStoreError.unreadable
        }
    }

    func save(_ layout: CustomWindowLayout) throws {
        var values = try load()
        if let index = values.firstIndex(where: { $0.id == layout.id }) {
            values[index] = layout
        } else {
            values.append(layout)
        }
        try persist(values)
    }

    func delete(id: UUID) throws {
        try persist(load().filter { $0.id != id })
    }

    private func persist(_ values: [CustomWindowLayout]) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(values)
        } catch {
            throw CustomWindowLayoutStoreError.saveFailed
        }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class InMemoryCustomWindowLayoutStore: CustomWindowLayoutStoring {
    private var layouts: [CustomWindowLayout]

    init(layouts: [CustomWindowLayout] = []) {
        self.layouts = layouts
    }

    func load() throws -> [CustomWindowLayout] {
        layouts
    }

    func save(_ layout: CustomWindowLayout) throws {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = layout
        } else {
            layouts.append(layout)
        }
    }

    func delete(id: UUID) throws {
        layouts.removeAll { $0.id == id }
    }
}
