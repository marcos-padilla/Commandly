import Testing
@testable import CommandKit

struct CommandKitTests {
    @Test func commandIDEquality() {
        let left = CommandID(rawValue: "open.settings")
        let right = CommandID(rawValue: "open.settings")
        let other = CommandID(rawValue: "open.about")
        #expect(left == right)
        #expect(left != other)
    }

    @Test func duplicateRegistrationThrows() async throws {
        let registry = CommandRegistry()
        let descriptor = CommandDescriptor(
            id: CommandID(rawValue: "demo.command"),
            title: "Demo",
            category: .productivity
        )
        try await registry.register(descriptor)
        await #expect(throws: CommandRegistryError.duplicateCommand(CommandID(rawValue: "demo.command"))) {
            try await registry.register(descriptor)
        }
        let count = await registry.count
        #expect(count == 1)
    }

    @Test func registryReturnsSortedDescriptors() async throws {
        let registry = CommandRegistry()
        try await registry.register(
            CommandDescriptor(id: CommandID(rawValue: "b"), title: "Bravo", category: .system)
        )
        try await registry.register(
            CommandDescriptor(id: CommandID(rawValue: "a"), title: "Alpha", category: .system)
        )
        let titles = await registry.allDescriptors().map(\.title)
        #expect(titles == ["Alpha", "Bravo"])
    }

    @Test func manifestRegistrationPreservesModeAndActions() async throws {
        let registry = CommandRegistry()
        let manifest = CommandManifest(
            id: BuiltInCommandID.clipboardHistory,
            title: "Clipboard History",
            systemImage: "clipboard",
            category: .productivity,
            mode: .view,
            defaultActions: [
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.copy,
                    title: "Copy",
                    isPrimary: true,
                    keyHint: .return
                )
            ]
        )
        try await registry.register(manifest)
        let loaded = await registry.manifest(for: BuiltInCommandID.clipboardHistory)
        #expect(loaded?.mode == .view)
        #expect(loaded?.defaultActions.first?.id == BuiltInCommandActionID.copy)
    }
}
