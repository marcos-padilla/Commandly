import Foundation
import Infrastructure
import Synchronization
import Testing
@testable import Commandly

nonisolated struct FileBrowserServiceTests {
    @Test func enumeratesOnlyOneLevelAndRejectsSymlinkAndTraversalEscapes() async throws {
        let fixture = try BrowserTemporaryFixture()
        defer { fixture.remove() }
        let store = BrowserTestFolderStore(bookmarks: [fixture.bookmark])
        let scopes = BrowserTestScopes()
        let service = AuthorizedFileBrowserService(folderAccessStore: store,
            resolver: BrowserTestResolver(urls: [fixture.bookmark: fixture.root], scopes: scopes))
        let root = try #require(try await service.roots().first)
        let location = FileBrowserLocation(rootID: root.id)
        let snapshot = try await service.list(location)
        #expect(snapshot.entries.map(\.name).contains("Folder"))
        #expect(snapshot.entries.map(\.name).contains("inside.txt"))
        #expect(snapshot.entries.map(\.name).contains("nested.txt") == false)
        #expect(snapshot.entries.map(\.name).contains(".hidden") == false)
        let link = try #require(snapshot.entries.first { $0.name == "Escape" })
        #expect(link.kind == .symbolicLink)
        #expect(link.isActionable == false)
        await #expect(throws: FileBrowserError.unsafeLocation) { try await service.list(link.location) }
        await #expect(throws: FileBrowserError.unsafeLocation) {
            try await service.list(FileBrowserLocation(rootID: root.id, components: ["..", "Outside"]))
        }
        await #expect(throws: FileBrowserError.unsafeLocation) {
            try await service.list(FileBrowserLocation(rootID: root.id, components: ["Folder/nested"]))
        }
        let folder = try #require(snapshot.entries.first { $0.name == "Folder" })
        let nested = try await service.list(folder.location)
        #expect(nested.entries.map(\.name) == ["nested.txt"])
        #expect(scopes.counts.started == scopes.counts.stopped)
    }

    @Test func boundedListingReportsTruncationAndBalancesScopeOnFailures() async throws {
        let fixture = try BrowserTemporaryFixture()
        defer { fixture.remove() }
        let scopes = BrowserTestScopes()
        let service = AuthorizedFileBrowserService(folderAccessStore: BrowserTestFolderStore(bookmarks: [fixture.bookmark]),
            resolver: BrowserTestResolver(urls: [fixture.bookmark: fixture.root], scopes: scopes), maximumEntries: 1)
        let root = try #require(try await service.roots().first)
        let snapshot = try await service.list(FileBrowserLocation(rootID: root.id))
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.isTruncated)
        await #expect(throws: FileBrowserError.folderUnavailable) {
            try await service.list(FileBrowserLocation(rootID: root.id, components: ["Missing"]))
        }
        #expect(scopes.counts.started == scopes.counts.stopped)
    }

    @Test func openRevalidatesIdentityAndCurrentAuthorizationWithoutFollowingLinks() async throws {
        let fixture = try BrowserTemporaryFixture()
        defer { fixture.remove() }
        let store = BrowserTestFolderStore(bookmarks: [fixture.bookmark])
        let scopes = BrowserTestScopes()
        let service = AuthorizedFileBrowserService(folderAccessStore: store,
            resolver: BrowserTestResolver(urls: [fixture.bookmark: fixture.root], scopes: scopes))
        let root = try #require(try await service.roots().first)
        let snapshot = try await service.list(FileBrowserLocation(rootID: root.id))
        let file = try #require(snapshot.entries.first { $0.name == "inside.txt" })
        let opener = BrowserTestOpener()
        try await service.open(file, using: opener)
        #expect(await opener.urls.count == 1)
        let opened = try #require(await opener.urls.first)
        #expect((opened as NSURL).filePathURL?.lastPathComponent == "inside.txt")

        // Swap the selected pathname for a link to an external fixture. The old row must fail.
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("inside.txt"))
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("inside.txt"),
            withDestinationURL: fixture.outside.appendingPathComponent("outside.txt"))
        await #expect(throws: FileBrowserError.itemChanged) { try await service.open(file, using: opener) }
        store.saveBookmarks([])
        await #expect(throws: FileBrowserError.noAuthorizedFolders) { try await service.open(file, using: opener) }
        #expect(await opener.urls.count == 1)
        #expect(scopes.counts.started == scopes.counts.stopped)
    }

    @Test func missingAndExpiredGrantsAreDistinctAndCancellationDoesNotEnumerate() async throws {
        let noAccess = AuthorizedFileBrowserService(folderAccessStore: BrowserTestFolderStore(bookmarks: []))
        await #expect(throws: FileBrowserError.noAuthorizedFolders) { try await noAccess.roots() }
        let stale = AuthorizedFileBrowserService(folderAccessStore: BrowserTestFolderStore(bookmarks: [Data([8])]),
            resolver: BrowserTestResolver(urls: [:], scopes: BrowserTestScopes()))
        await #expect(throws: FileBrowserError.authorizationUnavailable) { try await stale.roots() }
        let fixture = try BrowserTemporaryFixture()
        defer { fixture.remove() }
        let scopes = BrowserTestScopes()
        let service = AuthorizedFileBrowserService(folderAccessStore: BrowserTestFolderStore(bookmarks: [fixture.bookmark]),
            resolver: BrowserTestResolver(urls: [fixture.bookmark: fixture.root], scopes: scopes))
        let root = try #require(try await service.roots().first)
        let task = Task { try await service.list(FileBrowserLocation(rootID: root.id)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(scopes.counts.started == scopes.counts.stopped)
    }
}

@MainActor
struct FileBrowserModelTests {
    @Test func keyboardNavigationFiltersLocallyAndParentStopsAtTheAuthorizedRoot() async throws {
        let service = BrowserModelService()
        let navigation = BrowserTestNavigation()
        let model = makeModel(service: service, navigation: navigation)
        model.start()
        await model.waitForLoadingForTesting()
        #expect(model.rows.map(\.title) == ["Allowed"])
        model.performPrimary()
        await model.waitForLoadingForTesting()
        #expect(model.location == service.rootLocation)
        let requests = await service.listCount
        model.query = "folder"
        #expect(model.rows.map(\.title) == ["Folder"])
        #expect(await service.listCount == requests)
        model.performPrimary()
        await model.waitForLoadingForTesting()
        #expect(model.location == service.childLocation)
        #expect(model.handleEscape())
        await model.waitForLoadingForTesting()
        #expect(model.location == service.rootLocation)
        #expect(model.selectedRow?.title == "Folder")
        model.goUp()
        await model.waitForLoadingForTesting()
        #expect(model.location == nil)
        #expect(model.handleEscape() == false)
        model.goBack()
        #expect(navigation.backCount == 1)
    }

    @Test func lateNavigationAndStoppedSessionsCannotRestoreOldRows() async {
        let service = BrowserModelService()
        let model = makeModel(service: service)
        model.start()
        await model.waitForLoadingForTesting()
        await service.blockListing()
        model.performPrimary()
        await service.waitUntilListing()
        let previousLoad = Task.immediate { @MainActor in await model.waitForLoadingForTesting() }
        model.showRoots()
        await model.waitForLoadingForTesting()
        await service.releaseListing()
        await previousLoad.value
        #expect(model.location == nil)
        #expect(model.rows.map(\.title) == ["Allowed"])
        model.stop()
        model.start()
        model.refresh()
        #expect(model.rows.isEmpty)
        #expect(model.snapshot == nil)
    }

    @Test func stoppingDuringNavigationDiscardsTheLateSnapshot() async {
        let service = BrowserModelService()
        let model = makeModel(service: service)
        model.start()
        await model.waitForLoadingForTesting()
        await service.blockListing()
        model.performPrimary()
        await service.waitUntilListing()
        let previousLoad = Task.immediate { @MainActor in await model.waitForLoadingForTesting() }
        model.stop()
        await service.releaseListing()
        await previousLoad.value
        #expect(model.rows.isEmpty)
        #expect(model.snapshot == nil)
        #expect(model.location == nil)
    }

    @Test func duplicateOpenIsCoalescedAndCancelledCompletionCannotChangeStatus() async throws {
        let service = BrowserModelService()
        let model = makeModel(service: service)
        model.start()
        await model.waitForLoadingForTesting()
        model.performPrimary()
        await model.waitForLoadingForTesting()
        let file = try #require(model.rows.first { $0.title == "file.txt" })
        model.select(file.id)
        await service.blockOpening()
        model.performPrimary()
        await service.waitUntilOpening()
        model.performPrimary()
        #expect(await service.openCount == 1)
        model.query = "Folder"
        await service.releaseOpening()
        await model.waitForOpeningForTesting()
        #expect(model.statusMessage == nil)
        #expect(model.isOpening == false)
        model.stop()
    }

    @Test func missingAccessOffersExplicitSettingsAction() async {
        let navigation = BrowserTestNavigation()
        let model = FileBrowserViewModel(browser: BrowserNoAccessService(), opener: BrowserTestOpener(),
            onGoBack: {}, onOpenPermissions: { navigation.permissionsCount += 1 })
        model.start()
        await model.waitForLoadingForTesting()
        #expect(model.phase == .needsAccess)
        #expect(navigation.permissionsCount == 0)
        model.performPrimary()
        #expect(navigation.permissionsCount == 1)
        model.stop()
    }

    private func makeModel(service: BrowserModelService, navigation: BrowserTestNavigation = BrowserTestNavigation()) -> FileBrowserViewModel {
        FileBrowserViewModel(browser: service, opener: BrowserTestOpener(),
            onGoBack: { navigation.backCount += 1 }, onOpenPermissions: { navigation.permissionsCount += 1 })
    }
}

nonisolated private struct BrowserTemporaryFixture {
    let base: URL
    let root: URL
    let outside: URL
    let bookmark = Data([1, 2, 3])
    init() throws {
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Commandly-FileBrowser-\(UUID().uuidString)")
        root = base.appendingPathComponent("Allowed")
        outside = base.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: root.appendingPathComponent("inside.txt"))
        try Data("nested".utf8).write(to: root.appendingPathComponent("Folder/nested.txt"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))
        try Data("outside".utf8).write(to: outside.appendingPathComponent("outside.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Escape"), withDestinationURL: outside)
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
}

nonisolated private final class BrowserTestFolderStore: FolderAccessStoring {
    private let state: Mutex<[Data]>
    init(bookmarks: [Data]) { state = Mutex(bookmarks) }
    var bookmarkData: [Data] { state.withLock { $0 } }
    func saveBookmarks(_ bookmarks: [Data]) { state.withLock { $0 = bookmarks } }
    var hasUsableAccess: Bool { bookmarkData.isEmpty == false }
}

nonisolated private final class BrowserTestScopes: Sendable {
    struct Counts: Sendable { var started = 0; var stopped = 0 }
    private let state = Mutex(Counts())
    var counts: Counts { state.withLock { $0 } }
    func start() { state.withLock { $0.started += 1 } }
    func stop() { state.withLock { $0.stopped += 1 } }
}

nonisolated private struct BrowserTestResolver: FileBrowserRootResolving {
    let urls: [Data: URL]
    let scopes: BrowserTestScopes
    func resolve(_ bookmark: Data) throws -> URL {
        guard let url = urls[bookmark] else { throw FileBrowserError.authorizationUnavailable }
        return url
    }
    func startAccessing(_ url: URL) -> Bool { scopes.start(); return true }
    func stopAccessing(_ url: URL) { scopes.stop() }
}

private actor BrowserTestOpener: URLOpening {
    private(set) var urls: [URL] = []
    func openURL(_ url: URL) async throws { urls.append(url) }
}

@MainActor private final class BrowserTestNavigation {
    var backCount = 0
    var permissionsCount = 0
}

private actor BrowserModelService: FileBrowsing {
    nonisolated let rootLocation = FileBrowserLocation(rootID: "allowed")
    nonisolated let childLocation = FileBrowserLocation(rootID: "allowed", components: ["Folder"])
    private(set) var listCount = 0
    private(set) var openCount = 0
    private var holdsListing = false
    private var listing: CheckedContinuation<Void, Never>?
    private var listingObserver: CheckedContinuation<Void, Never>?
    private var holdsOpening = false
    private var opening: CheckedContinuation<Void, Never>?
    private var openingObserver: CheckedContinuation<Void, Never>?
    func roots() async throws -> [FileBrowserRoot] { [FileBrowserRoot(id: "allowed", name: "Allowed")] }
    func list(_ location: FileBrowserLocation) async throws -> FileBrowserSnapshot {
        listCount += 1
        if holdsListing {
            listingObserver?.resume(); listingObserver = nil
            await withCheckedContinuation { listing = $0 }
        }
        let identity = FileBrowserIdentity(device: 1, inode: 1)
        return FileBrowserSnapshot(location: location, entries: location == rootLocation ? [
            FileBrowserEntry(location: childLocation, name: "Folder", kind: .folder, identity: identity),
            FileBrowserEntry(location: FileBrowserLocation(rootID: "allowed", components: ["file.txt"]),
                             name: "file.txt", kind: .file, identity: identity)
        ] : [])
    }
    func open(_ entry: FileBrowserEntry, using opener: any URLOpening) async throws {
        openCount += 1
        if holdsOpening {
            openingObserver?.resume(); openingObserver = nil
            await withCheckedContinuation { opening = $0 }
        }
    }
    func blockListing() { holdsListing = true }
    func waitUntilListing() async { if listing != nil { return }; await withCheckedContinuation { listingObserver = $0 } }
    func releaseListing() { holdsListing = false; listing?.resume(); listing = nil }
    func blockOpening() { holdsOpening = true }
    func waitUntilOpening() async { if opening != nil { return }; await withCheckedContinuation { openingObserver = $0 } }
    func releaseOpening() { holdsOpening = false; opening?.resume(); opening = nil }
}

nonisolated private struct BrowserNoAccessService: FileBrowsing {
    func roots() async throws -> [FileBrowserRoot] { throw FileBrowserError.noAuthorizedFolders }
    func list(_ location: FileBrowserLocation) async throws -> FileBrowserSnapshot { throw FileBrowserError.noAuthorizedFolders }
    func open(_ entry: FileBrowserEntry, using opener: any URLOpening) async throws { throw FileBrowserError.noAuthorizedFolders }
}
