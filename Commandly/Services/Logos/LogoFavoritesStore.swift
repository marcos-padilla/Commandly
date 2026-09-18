import Foundation

nonisolated protocol LogoFavoritesStoring: Sendable {
    func favoriteIDs() async -> Set<Int>
    func setFavorite(_ isFavorite: Bool, id: Int) async
}

actor UserDefaultsLogoFavoritesStore: LogoFavoritesStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "logos.favorite-ids.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func favoriteIDs() -> Set<Int> {
        Set(defaults.array(forKey: key)?.compactMap {
            ($0 as? NSNumber)?.intValue
        } ?? [])
    }

    func setFavorite(_ isFavorite: Bool, id: Int) {
        var values = favoriteIDs()
        if isFavorite {
            values.insert(id)
        } else {
            values.remove(id)
        }
        defaults.set(values.sorted(), forKey: key)
    }
}

actor InMemoryLogoFavoritesStore: LogoFavoritesStoring {
    private var values: Set<Int>

    init(values: Set<Int> = []) {
        self.values = values
    }

    func favoriteIDs() -> Set<Int> { values }

    func setFavorite(_ isFavorite: Bool, id: Int) {
        if isFavorite {
            values.insert(id)
        } else {
            values.remove(id)
        }
    }
}
