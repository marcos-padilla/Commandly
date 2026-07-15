import Foundation
import Infrastructure
import SearchKit
import Testing
@testable import Commandly

struct FinderAIWorkspaceTests {
    @Test func opaqueHandlesAreSessionScopedAndInvalidatedOnEnd() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let firstSession = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: firstSession).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: firstSession)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })

        #expect(note.id.rawValue.uuidString.contains(fixture.root.path) == false)
        #expect(note.relativeLocation == "note.txt")

        let secondSession = await service.beginSession()
        await #expect(throws: FinderAIWorkspaceError.unknownItem) {
            try await service.metadata(for: [note.id], in: secondSession)
        }

        await service.endSession(firstSession)
        await #expect(throws: FinderAIWorkspaceError.unknownSession) {
            try await service.metadata(for: [note.id], in: firstSession)
        }
    }

    @Test func indexedSearchFiltersSiblingPrefixAndProtectsRoot() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let search = InMemoryFileSearchService(items: [
            fixture.searchItem(fixture.note),
            fixture.searchItem(fixture.outsideSecret),
            fixture.searchItem(fixture.root, kind: .folder)
        ])
        let service = await fixture.makeService(searchService: search)
        let session = await service.beginSession()
        _ = try await service.authorizedRoots(in: session)

        let page = try await service.search(
            FinderAISearchRequest(query: "note", limit: 10),
            in: session
        )

        #expect(page.items.map(\.displayName) == ["note.txt"])
        #expect(page.items.allSatisfy { $0.relativeLocation.hasPrefix("../") == false })
    }

    @Test func directoryListingIsNonrecursiveBoundedAndRejectsNonDirectories() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)

        #expect(page.items.contains { $0.displayName == "Folder" })
        #expect(page.items.contains { $0.displayName == "nested.txt" } == false)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })
        await #expect(throws: FinderAIWorkspaceError.expectedDirectory) {
            try await service.listDirectory(.item(note.id), limit: 10, in: session)
        }
        await #expect(throws: FinderAIWorkspaceError.limitExceeded) {
            try await service.listDirectory(
                .root(root.id),
                limit: FinderAIWorkspaceService.maximumDirectoryResultCount + 1,
                in: session
            )
        }
    }

    @Test func symlinksAndPackagesRemainOpaqueLeaves() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let link = try #require(page.items.first { $0.displayName == "Outside Link" })
        let package = try #require(page.items.first { $0.displayName == "Demo.app" })

        #expect(link.kind == .symbolicLink)
        #expect(package.kind == .package)
        await #expect(throws: FinderAIWorkspaceError.expectedDirectory) {
            try await service.listDirectory(.item(link.id), limit: 10, in: session)
        }
        await #expect(throws: FinderAIWorkspaceError.expectedDirectory) {
            try await service.listDirectory(.item(package.id), limit: 10, in: session)
        }

        let plan = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .rename(item: link.id, newName: "Renamed Link")
            ]),
            in: session
        )
        #expect(plan.warnings.contains(.affectsSymbolicLink))
        let approval = try await service.approveMutation(planID: plan.id, in: session)
        _ = try await service.executeApprovedMutation(approval)

        #expect(FileManager.default.fileExists(atPath: fixture.outsideSecret.path))
        #expect(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("Renamed Link").path
        ) || fixture.isSymbolicLink(fixture.root.appendingPathComponent("Renamed Link")))
    }

    @Test func safeNamesAndExactCollisionPoliciesAreEnforced() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })
        let folder = try #require(page.items.first { $0.displayName == "Folder" })

        for invalidName in ["../escape", ".hidden", " trailing ", "bad/name", "bad:name"] {
            await #expect(throws: FinderAIWorkspaceError.invalidName) {
                try await service.planMutation(
                    FinderAIMutationRequest(operations: [
                        .createFolder(parent: .root(root.id), name: invalidName)
                    ]),
                    in: session
                )
            }
        }

        await #expect(throws: FinderAIWorkspaceError.collision) {
            try await service.planMutation(
                FinderAIMutationRequest(operations: [
                    .copy(items: [note.id], destination: .item(folder.id), collisionPolicy: .fail)
                ]),
                in: session
            )
        }

        let keepBoth = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .copy(items: [note.id], destination: .item(folder.id), collisionPolicy: .keepBoth)
            ]),
            in: session
        )
        #expect(keepBoth.operations.first?.resultingNames == ["note 2.txt"])
        #expect(keepBoth.warnings.contains(.collisionRenamed))
    }

    @Test func writesRequireExactSingleUseApproval() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let destination = fixture.root.appendingPathComponent("Approved Folder", isDirectory: true)
        let plan = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .createFolder(parent: .root(root.id), name: "Approved Folder")
            ]),
            in: session
        )

        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
        let approval = try await service.approveMutation(planID: plan.id, in: session)
        await #expect(throws: FinderAIWorkspaceError.planAlreadyConsumed) {
            try await service.approveMutation(planID: plan.id, in: session)
        }
        let report = try await service.executeApprovedMutation(approval)
        #expect(report.completedCount == 1)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        await #expect(throws: FinderAIWorkspaceError.invalidApproval) {
            try await service.executeApprovedMutation(approval)
        }
    }

    @Test func identityChangesInvalidateAnApprovedPlanBeforeMutation() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })
        let plan = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .rename(item: note.id, newName: "changed.txt")
            ]),
            in: session
        )
        let approval = try await service.approveMutation(planID: plan.id, in: session)
        try Data("changed after preview".utf8).write(to: fixture.note)

        await #expect(throws: FinderAIWorkspaceError.itemChangedSincePreview) {
            try await service.executeApprovedMutation(approval)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.note.path))
    }

    @Test func trashUsesOnlyInjectedTrashPrimitive() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let trashMover = RecordingFinderAITrashMover()
        let service = await fixture.makeService(trashMover: trashMover)
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })
        let plan = try await service.planMutation(
            FinderAIMutationRequest(operations: [.trash(items: [note.id])]),
            in: session
        )
        #expect(plan.risk == .destructive)

        let approval = try await service.approveMutation(planID: plan.id, in: session)
        let report = try await service.executeApprovedMutation(approval)

        #expect(report.completedCount == 1)
        #expect(trashMover.urls == [fixture.note.standardizedFileURL])
        #expect(FileManager.default.fileExists(atPath: fixture.note.path))
    }

    @Test func textReadsAreBoundedOptInAndSingleUse() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let note = try #require(page.items.first { $0.displayName == "note.txt" })
        let plan = try await service.prepareTextRead(
            itemIDs: [note.id],
            maximumByteCount: 4,
            in: session
        )

        #expect(plan.items.map(\.displayName) == ["note.txt"])
        #expect(plan.items.first?.location.rootID == root.id)
        #expect(plan.items.first?.location.rootRelativePath == "note.txt")
        let displayedRootPath = (fixture.root.path as NSString).abbreviatingWithTildeInPath
        #expect(
            plan.items.first?.location.userVisibleDescription.contains(displayedRootPath) == true
        )
        let approval = try await service.approveTextRead(planID: plan.id, in: session)
        let content = try await service.readApprovedText(approval)
        #expect(content.first?.text == "hell")
        #expect(content.first?.wasTruncated == true)
        await #expect(throws: FinderAIWorkspaceError.invalidApproval) {
            try await service.readApprovedText(approval)
        }
        await #expect(throws: FinderAIWorkspaceError.limitExceeded) {
            try await service.prepareTextRead(
                itemIDs: [note.id],
                maximumByteCount: FinderAIWorkspaceService.maximumTextByteCount + 1,
                in: session
            )
        }
    }

    @Test func textReadTrimsOnlyAnIncompleteUTF8ScalarAtTheApprovedLimit() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let unicodeFile = fixture.root.appendingPathComponent("unicode.txt")
        try Data("A🙂B".utf8).write(to: unicodeFile)
        let service = await fixture.makeService()
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let page = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let item = try #require(page.items.first { $0.displayName == "unicode.txt" })
        let plan = try await service.prepareTextRead(
            itemIDs: [item.id],
            maximumByteCount: 2,
            in: session
        )
        let approval = try await service.approveTextRead(planID: plan.id, in: session)

        let contents = try await service.readApprovedText(approval)

        #expect(contents.first?.text == "A")
        #expect(contents.first?.wasTruncated == true)
    }

    @Test func plansExpireAndCancelledQueriesDoNoWork() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let clock = FinderAITestClock(Date(timeIntervalSince1970: 100))
        let service = await fixture.makeService(planLifetime: 5, now: { clock.value })
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let plan = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .createFolder(parent: .root(root.id), name: "Later")
            ]),
            in: session
        )
        clock.value = Date(timeIntervalSince1970: 106)
        await #expect(throws: FinderAIWorkspaceError.planExpired) {
            try await service.approveMutation(planID: plan.id, in: session)
        }

        let task = Task {
            try await service.search(FinderAISearchRequest(query: "note"), in: session)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func approvalPreviewsDisambiguateDuplicateNamesAcrossDirectoriesAndRoots() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let firstRoot = fixture.base.appendingPathComponent("One/Shared", isDirectory: true)
        let secondRoot = fixture.base.appendingPathComponent("Two/Shared", isDirectory: true)
        let files = [
            firstRoot.appendingPathComponent("Drafts/note.txt"),
            firstRoot.appendingPathComponent("Archive/note.txt"),
            secondRoot.appendingPathComponent("Drafts/note.txt")
        ]
        for file in files {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("approval preview".utf8).write(to: file)
        }
        let search = InMemoryFileSearchService(items: files.map { fixture.searchItem($0) })
        let service = await fixture.makeService(
            searchService: search,
            directAuthorizedRoots: [firstRoot, secondRoot]
        )
        let session = await service.beginSession()
        let roots = try await service.authorizedRoots(in: session)
        let page = try await service.search(
            FinderAISearchRequest(query: "note", limit: 10),
            in: session
        )
        #expect(roots.count == 2)
        #expect(roots.allSatisfy { $0.displayName == "Shared" })
        #expect(page.items.count == 3)

        let textPlan = try await service.prepareTextRead(
            itemIDs: page.items.map(\.id),
            maximumByteCount: 1_024,
            in: session
        )
        let textLocations = textPlan.items.map(\.location)
        #expect(Set(textLocations.map(\.rootID)) == Set(roots.map(\.id)))
        #expect(Set(textLocations.map(\.authorizedRootDisplayPath)) == Set([
            (firstRoot.path as NSString).abbreviatingWithTildeInPath,
            (secondRoot.path as NSString).abbreviatingWithTildeInPath,
        ]))
        #expect(Set(textLocations.map(\.userVisibleDescription)).count == 3)
        #expect(textLocations.allSatisfy { $0.rootRelativePath.hasSuffix("note.txt") })

        let duplicatePlan = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .duplicate(items: page.items.map(\.id), collisionPolicy: .fail)
            ]),
            in: session
        )
        let duplicate = try #require(duplicatePlan.operations.first)
        let duplicateDestinations = duplicate.destinations.compactMap { destination -> FinderAIApprovalLocation? in
            guard case .authorizedLocation(let location) = destination else { return nil }
            return location
        }
        #expect(Set(duplicate.sourceLocations.map(\.userVisibleDescription)).count == 3)
        #expect(Set(duplicateDestinations.map(\.userVisibleDescription)).count == 3)
        #expect(duplicateDestinations.allSatisfy {
            $0.rootRelativePath.hasSuffix("note copy.txt")
        })

        let trashPlan = try await service.planMutation(
            FinderAIMutationRequest(operations: [.trash(items: page.items.map(\.id))]),
            in: session
        )
        let trash = try #require(trashPlan.operations.first)
        #expect(Set(trash.sourceLocations.map(\.userVisibleDescription)).count == 3)
        #expect(trash.destinations == [.trash])
        #expect(trash.destinationDescription == "macOS Trash")
    }

    @Test func homeAncestorsAndInjectedVolumeRootsCannotBeAuthorized() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let userHome = fixture.base.appendingPathComponent("Users/Person", isDirectory: true)
        let homeAncestor = userHome.deletingLastPathComponent()
        let volumeRoot = fixture.base.appendingPathComponent("Volume", isDirectory: true)
        let safeRoot = fixture.base.appendingPathComponent("Safe", isDirectory: true)
        let homeAlias = fixture.base.appendingPathComponent("Home Alias", isDirectory: true)
        for directory in [userHome, volumeRoot, safeRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: homeAlias, withDestinationURL: userHome)

        let service = await fixture.makeService(
            directAuthorizedRoots: [userHome, homeAncestor, homeAlias, volumeRoot, safeRoot],
            protectedUserHomeDirectory: userHome,
            protectedVolumeRoots: [volumeRoot]
        )
        let session = await service.beginSession()
        let roots = try await service.authorizedRoots(in: session)

        #expect(roots.map(\.displayName) == ["Safe"])
    }

    @Test func commandlyOwnedDataIsExcludedInsideABroaderAuthorizedRoot() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let ownedDirectory = fixture.root.appendingPathComponent(
            "Commandly Data",
            isDirectory: true
        )
        let ownedFile = ownedDirectory.appendingPathComponent("private.txt")
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        try Data("private app state".utf8).write(to: ownedFile)
        let search = InMemoryFileSearchService(items: [
            fixture.searchItem(ownedFile),
            fixture.searchItem(fixture.note)
        ])
        let service = await fixture.makeService(
            searchService: search,
            directAuthorizedRoots: [ownedDirectory, fixture.root],
            commandlyOwnedDataDirectories: [ownedDirectory]
        )
        let session = await service.beginSession()
        let authorizedRoots = try await service.authorizedRoots(in: session)
        let root = try #require(authorizedRoots.first)
        let listing = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let results = try await service.search(
            FinderAISearchRequest(query: "note", limit: 20),
            in: session
        )

        #expect(authorizedRoots.count == 1)
        #expect(listing.items.contains { $0.displayName == "Commandly Data" } == false)
        #expect(results.items.map(\.displayName) == ["note.txt"])
        await #expect(throws: FinderAIWorkspaceError.unauthorized) {
            try await service.planMutation(
                FinderAIMutationRequest(operations: [
                    .createFolder(parent: .root(root.id), name: "Commandly Data")
                ]),
                in: session
            )
        }
    }

    @Test func automaticSearchCannotProbeContentsOrHiddenAbsolutePathComponents() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let contentOnly = FileSearchItem(
            url: fixture.root.appendingPathComponent("opaque.txt"),
            name: "opaque.txt",
            parentPath: fixture.root.path,
            kind: .file,
            contentTypeDescription: "Text",
            matchKind: .contents
        )
        try Data("private-token".utf8).write(to: contentOnly.url)
        let search = InMemoryFileSearchService(items: [contentOnly, fixture.searchItem(fixture.note)])
        let service = await fixture.makeService(searchService: search)
        let session = await service.beginSession()

        let contentProbe = try await service.search(
            FinderAISearchRequest(query: "private-token", limit: 20),
            in: session
        )
        let absolutePathProbe = try await service.search(
            FinderAISearchRequest(query: fixture.base.lastPathComponent, limit: 20),
            in: session
        )

        #expect(contentProbe.items.isEmpty)
        #expect(absolutePathProbe.items.isEmpty)
        let requests = await search.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { request in
            request.includesFileNames
                && request.includesFilePaths == false
                && request.includesFileContents == false
                && request.includesMetadata == false
                && request.includesTags == false
                && request.scopeURLs == [fixture.root.standardizedFileURL]
        })
    }

    @Test func nestedAuthorizationRootsAndTheirAncestorsCannotBeMutationSources() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let outer = fixture.base.appendingPathComponent("Outer", isDirectory: true)
        let exactNestedRoot = outer.appendingPathComponent("Important", isDirectory: true)
        let ancestor = outer.appendingPathComponent("Projects", isDirectory: true)
        let deeplyNestedRoot = ancestor.appendingPathComponent("Protected", isDirectory: true)
        for directory in [exactNestedRoot, deeplyNestedRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let service = await fixture.makeService(
            directAuthorizedRoots: [outer, exactNestedRoot, deeplyNestedRoot]
        )
        let session = await service.beginSession()
        let roots = try await service.authorizedRoots(in: session)
        let outerRoot = try #require(roots.first { $0.displayName == "Outer" })

        let listing = try await service.listDirectory(.root(outerRoot.id), limit: 20, in: session)

        #expect(listing.items.contains { $0.displayName == "Important" } == false)
        let projects = try #require(listing.items.first { $0.displayName == "Projects" })
        await #expect(throws: FinderAIWorkspaceError.rootIsProtected) {
            try await service.planMutation(
                FinderAIMutationRequest(operations: [.trash(items: [projects.id])]),
                in: session
            )
        }
    }

    @Test func ancestorOfCommandlyOwnedDataCannotBeMutationSource() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let broadRoot = fixture.base.appendingPathComponent("Library", isDirectory: true)
        let ancestor = broadRoot.appendingPathComponent("Application Support", isDirectory: true)
        let ownedDirectory = ancestor.appendingPathComponent("Commandly", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let service = await fixture.makeService(
            directAuthorizedRoots: [broadRoot],
            commandlyOwnedDataDirectories: [ownedDirectory]
        )
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let listing = try await service.listDirectory(.root(root.id), limit: 20, in: session)
        let applicationSupport = try #require(
            listing.items.first { $0.displayName == "Application Support" }
        )

        await #expect(throws: FinderAIWorkspaceError.unauthorized) {
            try await service.planMutation(
                FinderAIMutationRequest(operations: [.trash(items: [applicationSupport.id])]),
                in: session
            )
        }
    }

    @Test func everyBatchActionRevalidatesItsDestinationImmediatelyBeforeExecution() async throws {
        let fixture = try FinderAITestFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("copy-me.txt")
        let destination = fixture.root.appendingPathComponent("Destination", isDirectory: true)
        let outsideDestination = fixture.outside.appendingPathComponent("Escaped", isDirectory: true)
        try Data("copy".utf8).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outsideDestination,
            withIntermediateDirectories: true
        )
        let trashMover = DestinationReplacingFinderAITrashMover(
            destination: destination,
            replacementTarget: outsideDestination
        )
        let service = await fixture.makeService(trashMover: trashMover)
        let session = await service.beginSession()
        let root = try #require(try await service.authorizedRoots(in: session).first)
        let listing = try await service.listDirectory(.root(root.id), limit: 30, in: session)
        let first = try #require(listing.items.first { $0.displayName == "note.txt" })
        let copySource = try #require(listing.items.first { $0.displayName == "copy-me.txt" })
        let destinationItem = try #require(listing.items.first { $0.displayName == "Destination" })
        let plan = try await service.planMutation(
            FinderAIMutationRequest(operations: [
                .trash(items: [first.id]),
                .copy(
                    items: [copySource.id],
                    destination: .item(destinationItem.id),
                    collisionPolicy: .fail
                ),
            ]),
            in: session
        )
        let approval = try await service.approveMutation(planID: plan.id, in: session)

        let report = try await service.executeApprovedMutation(approval)

        #expect(report.results.count == 2)
        #expect(report.results.first?.status == .completed)
        #expect(report.results.last?.status == .failed(.itemChangedSincePreview))
        #expect(FileManager.default.fileExists(
            atPath: outsideDestination.appendingPathComponent("copy-me.txt").path
        ) == false)
    }
}

nonisolated private struct NoOpFinderAIRevealer: FileRevealing {
    func revealInFinder(urls: [URL]) async throws {
        _ = urls
    }
}

nonisolated private final class RecordingFinderAITrashMover: FinderAITrashMoving, @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []

    var urls: [URL] {
        lock.withLock { storedURLs }
    }

    func moveToTrash(_ url: URL) throws {
        lock.withLock { storedURLs.append(url.standardizedFileURL) }
    }
}

/// Immutable test hook; its only effect is a synchronous, deterministic filesystem replacement.
nonisolated private final class DestinationReplacingFinderAITrashMover:
    FinderAITrashMoving, @unchecked Sendable {
    private let destination: URL
    private let replacementTarget: URL

    init(destination: URL, replacementTarget: URL) {
        self.destination = destination
        self.replacementTarget = replacementTarget
    }

    func moveToTrash(_: URL) throws {
        let fileManager = FileManager.default
        try fileManager.removeItem(at: destination)
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: replacementTarget)
    }
}

nonisolated private final class FinderAITestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        self.storedValue = value
    }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class FinderAITestFixture {
    let base: URL
    let root: URL
    let outside: URL
    let note: URL
    let folder: URL
    let outsideSecret: URL

    init() throws {
        let manager = FileManager.default
        base = manager.temporaryDirectory
            .appendingPathComponent("Commandly-FinderAI-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Scope", isDirectory: true)
        outside = base.appendingPathComponent("Scope2", isDirectory: true)
        note = root.appendingPathComponent("note.txt")
        folder = root.appendingPathComponent("Folder", isDirectory: true)
        outsideSecret = outside.appendingPathComponent("outside.txt")

        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("hello world".utf8).write(to: note)
        try Data("collision".utf8).write(to: folder.appendingPathComponent("note.txt"))
        try Data("nested".utf8).write(to: folder.appendingPathComponent("nested.txt"))
        try Data("outside".utf8).write(to: outsideSecret)

        let package = root.appendingPathComponent("Demo.app", isDirectory: true)
        try manager.createDirectory(
            at: package.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("package".utf8).write(
            to: package.appendingPathComponent("Contents/payload.txt")
        )
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("Outside Link"),
            withDestinationURL: outsideSecret
        )
    }

    func makeService(
        searchService: any FileSearching = InMemoryFileSearchService(),
        trashMover: any FinderAITrashMoving = NativeFinderAITrashMover(),
        directAuthorizedRoots: [URL]? = nil,
        protectedUserHomeDirectory: URL? = nil,
        protectedVolumeRoots: [URL] = [],
        commandlyOwnedDataDirectories: [URL] = [],
        planLifetime: TimeInterval = 120,
        now: @escaping @Sendable () -> Date = { Date() }
    ) async -> FinderAIWorkspaceService {
        let folderAccessStore = await MainActor.run { InMemoryFolderAccessStore() }
        return FinderAIWorkspaceService(
            folderAccessStore: folderAccessStore,
            searchService: searchService,
            fileRevealer: NoOpFinderAIRevealer(),
            trashMover: trashMover,
            directAuthorizedRoots: directAuthorizedRoots ?? [root],
            protectedUserHomeDirectory: protectedUserHomeDirectory
                ?? base.appendingPathComponent("Unrelated Home", isDirectory: true),
            protectedVolumeRoots: protectedVolumeRoots,
            commandlyOwnedDataDirectories: commandlyOwnedDataDirectories,
            planLifetime: planLifetime,
            now: now
        )
    }

    func searchItem(_ url: URL, kind: FileSearchItemKind = .file) -> FileSearchItem {
        FileSearchItem(
            url: url,
            name: url.lastPathComponent,
            parentPath: url.deletingLastPathComponent().path,
            kind: kind,
            contentTypeDescription: kind == .folder ? "Folder" : "Text"
        )
    }

    func isSymbolicLink(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType)
            == .typeSymbolicLink
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}
