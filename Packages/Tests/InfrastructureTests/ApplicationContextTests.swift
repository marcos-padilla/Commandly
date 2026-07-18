import Testing
@testable import Infrastructure

@Suite("Application context")
struct ApplicationContextTests {
    @Test @MainActor
    func inMemoryProviderReturnsOneFrozenSnapshot() {
        let context = FrontmostApplicationContext(
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            localizedName: "Editor"
        )
        let provider = InMemoryFrontmostApplicationContextProvider(context: context)

        #expect(provider.snapshot() == context)
    }
}
