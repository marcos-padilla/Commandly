#if DEBUG
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct FileBrowserDebugFixtureTests {
    @Test func fixtureSupportsNestedNavigationAndNeverOpensARealURL() async throws {
        let fixture = FileBrowserDebugFixture()
        let roots = try await fixture.roots()
        #expect(roots.map(\.name) == ["Design Workspace", "Shared Samples"])
        let root = try #require(roots.first)
        let top = try await fixture.list(FileBrowserLocation(rootID: root.id))
        let project = try #require(top.entries.first { $0.name == "Projects" })
        let nested = try await fixture.list(project.location)
        #expect(nested.entries.map(\.name) == ["Archive", "Assets", "Launch plan.md"])
        let file = try #require(nested.entries.first { $0.name == "Launch plan.md" })
        let opener = FileBrowserFixtureOpener()
        try await fixture.open(file, using: opener)
        #expect(await fixture.opened == [file.location])
        #expect(await opener.count == 0)
        let link = try #require(top.entries.first { $0.kind == .symbolicLink })
        await #expect(throws: FileBrowserError.unsupportedItem) { try await fixture.open(link, using: opener) }
    }
}

private actor FileBrowserFixtureOpener: URLOpening {
    private(set) var count = 0
    func openURL(_ url: URL) async throws { count += 1 }
}
#endif
