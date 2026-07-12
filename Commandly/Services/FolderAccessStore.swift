import Foundation

/// Persists security-scoped bookmarks for user-selected folders.
protocol FolderAccessStoring: AnyObject, Sendable {
    var bookmarkData: [Data] { get }
    func saveBookmarks(_ bookmarks: [Data])
    var hasUsableAccess: Bool { get }
}

/// UserDefaults-backed folder bookmark store.
///
/// Bookmarks are not secrets, but they are opaque capability tokens and must not be logged.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set of this blob.
final class UserDefaultsFolderAccessStore: FolderAccessStoring, @unchecked Sendable {
    private enum Key {
        static let bookmarks = "settings.folderAccessBookmarks"
        static let bookmarkFormatVersion = "settings.folderAccessBookmarkFormatVersion"
    }
    private static let currentBookmarkFormatVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var bookmarkData: [Data] {
        guard defaults.integer(forKey: Key.bookmarkFormatVersion)
            == Self.currentBookmarkFormatVersion else {
            return []
        }
        return defaults.array(forKey: Key.bookmarks) as? [Data] ?? []
    }

    func saveBookmarks(_ bookmarks: [Data]) {
        defaults.set(bookmarks, forKey: Key.bookmarks)
        defaults.set(
            Self.currentBookmarkFormatVersion,
            forKey: Key.bookmarkFormatVersion
        )
    }

    var hasUsableAccess: Bool {
        bookmarkData.contains { data in
            var isStale = false
            guard
                (try? URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )) != nil
            else {
                return false
            }
            return !isStale
        }
    }
}

/// In-memory folder access store for tests and previews.
///
/// `@unchecked Sendable`: mutated from `@MainActor` app/test code in this foundation phase.
final class InMemoryFolderAccessStore: FolderAccessStoring, @unchecked Sendable {
    private(set) var bookmarkData: [Data]
    private var forceUsable: Bool

    init(bookmarkData: [Data] = [], forceUsable: Bool = false) {
        self.bookmarkData = bookmarkData
        self.forceUsable = forceUsable
    }

    func saveBookmarks(_ bookmarks: [Data]) {
        bookmarkData = bookmarks
        forceUsable = !bookmarks.isEmpty
    }

    var hasUsableAccess: Bool {
        forceUsable || !bookmarkData.isEmpty
    }
}
