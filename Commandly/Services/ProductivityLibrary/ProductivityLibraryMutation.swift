import Foundation

/// Compare-and-write operations prevent one editor from replacing another editor's note or list.
nonisolated enum ProductivityLibraryMutation: Equatable, Sendable {
    case create(ProductivityLibraryItem)
    case replace(ProductivityLibraryItem, expected: ProductivityLibraryItem)
    case delete(expected: ProductivityLibraryItem)

    static func applying(_ changes: [Self], to items: [ProductivityLibraryItem]) throws -> [ProductivityLibraryItem] {
        guard Set(items.map(\.id)).count == items.count else {
            throw ProductivityLibraryPersistenceError.conflict
        }
        var updated = items
        for change in changes {
            switch change {
            case .create(let item):
                guard updated.contains(where: { $0.id == item.id }) == false else {
                    throw ProductivityLibraryPersistenceError.conflict
                }
                updated.append(item)
            case .replace(let item, let expected):
                guard item.id == expected.id,
                      let index = updated.firstIndex(where: { $0.id == expected.id }),
                      updated[index] == expected else {
                    throw ProductivityLibraryPersistenceError.conflict
                }
                updated[index] = item
            case .delete(let expected):
                guard let index = updated.firstIndex(where: { $0.id == expected.id }),
                      updated[index] == expected else {
                    throw ProductivityLibraryPersistenceError.conflict
                }
                updated.remove(at: index)
            }
        }
        return updated
    }
}
