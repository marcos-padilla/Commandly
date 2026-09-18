import Foundation
import Infrastructure

/// Construction performs no disk, permission or native operation.
struct AppMenusApplicationServices: Sendable {
    let client: any CompanionAppMenuCalling
    let favorites: any CompanionMenuFavoritesStoring
    static func live(client: any CompanionAppMenuCalling) -> Self {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Commandly/AppMenus/favorites.json")
        return .init(client: client, favorites: FileCompanionMenuFavoritesStore(url: url))
    }
    static var unavailable: Self { .init(client: UnavailableCompanionAppMenuCaller(), favorites: MemoryCompanionMenuFavoritesStore()) }
}
private actor MemoryCompanionMenuFavoritesStore: CompanionMenuFavoritesStoring {
    private var values: Set<CompanionMenuIdentity> = []
    func load() -> Set<CompanionMenuIdentity> { values }
    func save(_ values: Set<CompanionMenuIdentity>) throws {
        guard values.count <= 100, values.allSatisfy(\.isValid) else { throw CompanionAppMenuError.persistence }
        self.values = values
    }
}
