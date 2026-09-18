import Foundation
import Infrastructure

/// Injectable bookmark/scope boundary; tests use temporary roots without real grants.
nonisolated protocol FileBrowserRootResolving: Sendable {
    func resolve(_ bookmark: Data) throws -> URL
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

nonisolated struct SecurityScopedFileBrowserRootResolver: FileBrowserRootResolving {
    func resolve(_ bookmark: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        guard isStale == false, url.isFileURL else { throw FileBrowserError.authorizationUnavailable }
        return url.standardizedFileURL
    }
    func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}
