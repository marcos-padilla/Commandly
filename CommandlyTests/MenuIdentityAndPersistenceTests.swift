@testable import Commandly
import SystemCompanionKit
import Foundation
import Infrastructure
import Testing

struct MenuIdentityAndPersistenceTests {
    @Test func fingerprintRejectsEveryChangedPathComponentAndDisabledState() throws {
        let value = candidate()
        try value.requireUnchanged(path: value.path, enabled: true)
        let changes: [CompanionMenuPathComponent] = [
            .init(index: 2, role: "AXMenuItem", title: "Generated Action", identifier: "generated.action", shortcut: "g:0:5:0"),
            .init(index: 1, role: "AXButton", title: "Generated Action", identifier: "generated.action", shortcut: "g:0:5:0"),
            .init(index: 1, role: "AXMenuItem", title: "Replacement", identifier: "generated.action", shortcut: "g:0:5:0"),
            .init(index: 1, role: "AXMenuItem", title: "Generated Action", identifier: "replacement", shortcut: "g:0:5:0"),
            .init(index: 1, role: "AXMenuItem", title: "Generated Action", identifier: "generated.action", shortcut: "g:1:5:0")
        ]
        for change in changes {
            #expect(throws: CompanionAppMenuError.stale) { try value.requireUnchanged(path: Array(value.path.dropLast()) + [change], enabled: true) }
        }
        #expect(throws: CompanionAppMenuError.stale) { try value.requireUnchanged(path: value.path, enabled: false) }
        #expect(throws: CompanionAppMenuError.stale) { try value.requireUnchanged(path: Array(value.path.dropFirst()), enabled: true) }
    }
    @Test func identityIsStableAcrossSessionsButDistinguishesAppPathAndIndex() throws {
        let first = candidate(); let second = candidate()
        #expect(try first.identity(bundle: "generated.one") == second.identity(bundle: "generated.one"))
        #expect(try first.identity(bundle: "generated.one") != first.identity(bundle: "generated.two"))
        #expect(try first.identity(bundle: "generated.one") != candidate("Other").identity(bundle: "generated.one"))
        let invalid = CompanionMenuCandidate(path: [.init(index: 500, role: "AXMenuItem", title: "A")], enabled: true)
        #expect(throws: CompanionAppMenuError.invalidData) { _ = try invalid.identity(bundle: "generated.one") }
    }
    @Test func realPersistenceRoundTripsOnlyExplicitHashedIdentityPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CommandlyMenuFavorites-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("favorites.json")
        let store = FileCompanionMenuFavoritesStore(url: url)
        #expect(try await store.load().isEmpty)
        let identity = try candidate("PRIVATE GENERATED MENU TITLE").identity(bundle: "generated.fixture")
        try await store.save([identity])
        #expect(try await store.load() == [identity])
        let bytes = try Data(contentsOf: url)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(!text.contains("PRIVATE") && !text.contains("AXMenu") && !text.contains("Generated Menu"))
        #expect(!text.contains("session") && !text.contains("target") && !text.contains("title"))
        try await store.save([]); #expect(try await store.load().isEmpty)
    }
    @Test func persistenceRejectsSymlinkOversizeAndInvalidVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CommandlyMenuInvalid-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.json"); let link = root.appendingPathComponent("link.json")
        try Data("{\"version\":2,\"favorites\":[]}".utf8).write(to: target)
        let store = FileCompanionMenuFavoritesStore(url: target)
        await #expect(throws: CompanionAppMenuError.persistence) { _ = try await store.load() }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = FileCompanionMenuFavoritesStore(url: link)
        await #expect(throws: CompanionAppMenuError.persistence) { _ = try await linked.load() }
        await #expect(throws: CompanionAppMenuError.persistence) { try await linked.save([]) }
        try Data(repeating: 32, count: 262_145).write(to: target)
        await #expect(throws: CompanionAppMenuError.persistence) { _ = try await store.load() }
    }
    @Test func canonicalWireRejectsUnknownKeysCasesAndOversizedPayloads() throws {
        let request = CompanionAppMenuRequest.invoke(.init(session: UUID(), target: UUID()))
        let bytes = try CompanionAppMenuWire.encodeRequest(request)
        #expect(try CompanionAppMenuWire.decodeRequest(bytes) == request)
        var extra = bytes; extra.removeLast(); extra.append(contentsOf: ",\"pid\":123}".utf8)
        #expect(throws: CompanionAppMenuError.invalidData) { _ = try CompanionAppMenuWire.decodeRequest(extra) }
        #expect(throws: CompanionAppMenuError.invalidData) { _ = try CompanionAppMenuWire.decodeRequest(Data("{\"shell\":{}}".utf8)) }
        #expect(throws: CompanionAppMenuError.invalidData) { _ = try CompanionAppMenuWire.decodeRequest(Data(repeating: 32, count: 2049)) }
        let duplicate = Data("{\"snapshot\":{},\"snapshot\":{}}".utf8)
        #expect(throws: CompanionAppMenuError.invalidData) { _ = try CompanionAppMenuWire.decodeRequest(duplicate) }
        let deep = Data((String(repeating: "[", count: 17) + String(repeating: "]", count: 17)).utf8)
        #expect(throws: CompanionAppMenuError.invalidData) { _ = try CompanionAppMenuWire.decodeReply(deep) }
    }
}
