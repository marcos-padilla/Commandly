import CommandKit
import Foundation
import ModuleKit
import Testing
@testable import ModuleRuntime

// MARK: - Test doubles

@MainActor
final class ActivationCounter {
    private(set) var activationCount = 0
    private(set) var lifecycleStarts = 0
    private(set) var lifecycleStops = 0

    func recordActivation() { activationCount += 1 }
    func recordStart() { lifecycleStarts += 1 }
    func recordStop() { lifecycleStops += 1 }
}

@MainActor
final class SpyLifecycle: ModuleLifecycle {
    private let counter: ActivationCounter
    private let deactivationDecision: ModuleDeactivationDecision

    init(counter: ActivationCounter, deactivationDecision: ModuleDeactivationDecision = .allow) {
        self.counter = counter
        self.deactivationDecision = deactivationDecision
    }

    func activate() async throws { counter.recordStart() }
    func prepareForDeactivation() async -> ModuleDeactivationDecision { deactivationDecision }
    func deactivate() async { counter.recordStop() }
}

@MainActor
struct EchoHandler: ModuleCommandHandling {
    func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        .succeeded(
            message: invocation.commandID.rawValue,
            output: ModuleCommandOutput(["id": .string(invocation.commandID.rawValue)])
        )
    }
}

@MainActor
struct TestAssembly: ModuleAssembly {
    let manifest: ModuleManifest
    let commandDefinitions: [ModuleCommandDefinition]
    var settings: ModuleSettingsContribution?
    var documentation: ModuleDocumentationContribution?
    let counter: ActivationCounter?
    let deactivationDecision: ModuleDeactivationDecision
    let activationError: (any Error)?

    init(
        manifest: ModuleManifest,
        commandDefinitions: [ModuleCommandDefinition],
        settings: ModuleSettingsContribution? = nil,
        documentation: ModuleDocumentationContribution? = nil,
        counter: ActivationCounter? = nil,
        deactivationDecision: ModuleDeactivationDecision = .allow,
        activationError: (any Error)? = nil
    ) {
        self.manifest = manifest
        self.commandDefinitions = commandDefinitions
        self.settings = settings
        self.documentation = documentation
        self.counter = counter
        self.deactivationDecision = deactivationDecision
        self.activationError = activationError
    }

    func activate() async throws -> ModuleActivation {
        if let activationError { throw activationError }
        counter?.recordActivation()
        // Yield so concurrent activation requests genuinely overlap.
        await Task.yield()
        var handlers: [CommandID: any ModuleCommandHandling] = [:]
        for definition in commandDefinitions {
            handlers[definition.id] = EchoHandler()
        }
        return ModuleActivation(
            handlers: handlers,
            lifecycle: counter.map {
                SpyLifecycle(counter: $0, deactivationDecision: deactivationDecision)
            }
        )
    }
}

@MainActor
final class ToggleableEnablement: ModuleEnablementProviding {
    var disabled: Set<ModuleID> = []
    func isEnabled(_ moduleID: ModuleID) -> Bool { disabled.contains(moduleID) == false }
}

@MainActor
final class StubCapabilityEvaluator: ModuleCapabilityEvaluating {
    var unmet: ModuleCapabilityRequirement?
    func firstUnmetRequirement(
        among requirements: [ModuleCapabilityRequirement]
    ) -> ModuleCapabilityRequirement? {
        guard let unmet, requirements.contains(unmet) else { return nil }
        return unmet
    }
}

// MARK: - Fixtures

@MainActor
enum Fixture {
    static func definition(
        _ id: String,
        mode: ModuleCommandExecutionMode = .direct,
        exposure: ModuleCommandAIExposure = .hidden
    ) -> ModuleCommandDefinition {
        ModuleCommandDefinition(
            manifest: CommandManifest(
                id: CommandID(rawValue: id),
                title: id,
                systemImage: "circle",
                category: .productivity,
                mode: .action
            ),
            summary: "Summary for \(id).",
            policy: ModuleCommandPolicy(
                executionMode: mode,
                effect: .localMutation,
                aiExposure: exposure
            )
        )
    }

    static func manifest(
        _ id: String,
        commands: [ModuleCommandDefinition],
        status: ModuleFeatureStatus = .shipping,
        policy: ModuleActivationPolicy = .onDemand,
        capabilities: [ModuleCapabilityRequirement] = [],
        articles: [String] = []
    ) -> ModuleManifest {
        ModuleManifest(
            id: ModuleID(rawValue: id),
            title: id,
            summary: "Summary for \(id).",
            status: status,
            ownedCommandIDs: commands.map(\.id),
            capabilities: capabilities,
            activationPolicy: policy,
            documentationArticleIDs: articles
        )
    }

    static func assembly(
        _ id: String,
        commandIDs: [String],
        counter: ActivationCounter? = nil,
        status: ModuleFeatureStatus = .shipping,
        policy: ModuleActivationPolicy = .onDemand,
        capabilities: [ModuleCapabilityRequirement] = [],
        deactivationDecision: ModuleDeactivationDecision = .allow
    ) -> TestAssembly {
        let commands = commandIDs.map { definition($0) }
        return TestAssembly(
            manifest: manifest(
                id,
                commands: commands,
                status: status,
                policy: policy,
                capabilities: capabilities
            ),
            commandDefinitions: commands,
            counter: counter,
            deactivationDecision: deactivationDecision
        )
    }
}

// MARK: - Registration and validation

@MainActor
struct ModuleHostRegistrationTests {
    @Test func registersAndProjectsCatalogWithoutActivating() async throws {
        let counter = ActivationCounter()
        let host = ModuleHost()
        try host.register(Fixture.assembly("a", commandIDs: ["a.two", "a.one"], counter: counter))

        #expect(counter.activationCount == 0)
        #expect(host.isActivated(ModuleID(rawValue: "a")) == false)
        #expect(host.commandDefinitions().map(\.id.rawValue) == ["a.one", "a.two"])
    }

    @Test func catalogOrderIsDeterministicAcrossModules() throws {
        let host = ModuleHost()
        try host.register(Fixture.assembly("z", commandIDs: ["z.b", "z.a"]))
        try host.register(Fixture.assembly("a", commandIDs: ["a.b", "a.a"]))

        // Registration order for modules; identifier order within a module.
        #expect(host.commandDefinitions().map(\.id.rawValue) == ["z.a", "z.b", "a.a", "a.b"])
        #expect(host.manifests().map(\.id.rawValue) == ["z", "a"])
    }

    @Test func duplicateModuleIsRejected() throws {
        let host = ModuleHost()
        try host.register(Fixture.assembly("a", commandIDs: ["a.one"]))
        #expect(throws: ModuleHostError.duplicateModule(ModuleID(rawValue: "a"))) {
            try host.register(Fixture.assembly("a", commandIDs: ["a.two"]))
        }
    }

    @Test func duplicateCommandAcrossModulesIsRejected() throws {
        let host = ModuleHost()
        try host.register(Fixture.assembly("a", commandIDs: ["shared.command"]))
        #expect(throws: ModuleHostError.duplicateCommand(CommandID(rawValue: "shared.command"))) {
            try host.register(Fixture.assembly("b", commandIDs: ["shared.command"]))
        }
    }

    @Test func commandNotListedInManifestIsRejected() throws {
        let declared = Fixture.definition("a.one")
        let undeclared = Fixture.definition("a.two")
        let assembly = TestAssembly(
            manifest: Fixture.manifest("a", commands: [declared]),
            commandDefinitions: [declared, undeclared]
        )
        let host = ModuleHost()
        #expect(
            throws: ModuleHostError.commandNotOwned(
                module: ModuleID(rawValue: "a"),
                command: CommandID(rawValue: "a.two")
            )
        ) {
            try host.register(assembly)
        }
    }

    @Test func manifestCommandWithoutDefinitionIsRejected() throws {
        let declared = Fixture.definition("a.one")
        let ghost = Fixture.definition("a.ghost")
        let assembly = TestAssembly(
            manifest: Fixture.manifest("a", commands: [declared, ghost]),
            commandDefinitions: [declared]
        )
        let host = ModuleHost()
        #expect(
            throws: ModuleHostError.missingCommandDefinition(
                module: ModuleID(rawValue: "a"),
                command: CommandID(rawValue: "a.ghost")
            )
        ) {
            try host.register(assembly)
        }
    }

    @Test func duplicateConfigurationVariableIsRejected() throws {
        let command = Fixture.definition("a.one")
        let assembly = TestAssembly(
            manifest: Fixture.manifest("a", commands: [command]),
            commandDefinitions: [command],
            settings: ModuleSettingsContribution(fields: [
                ModuleConfigurationField(
                    id: "one", variable: "shared", title: "One",
                    kind: .toggle, defaultValue: .boolean(true)
                ),
                ModuleConfigurationField(
                    id: "two", variable: "shared", title: "Two",
                    kind: .toggle, defaultValue: .boolean(true)
                )
            ])
        )
        let host = ModuleHost()
        #expect(throws: (any Error).self) { try host.register(assembly) }
    }

    @Test func configurationDefaultMustMatchItsKind() throws {
        let command = Fixture.definition("a.one")
        let assembly = TestAssembly(
            manifest: Fixture.manifest("a", commands: [command]),
            commandDefinitions: [command],
            settings: ModuleSettingsContribution(fields: [
                ModuleConfigurationField(
                    id: "one", variable: "one", title: "One",
                    kind: .toggle, defaultValue: .text("yes")
                )
            ])
        )
        let host = ModuleHost()
        #expect(
            throws: ModuleHostError.invalidConfigurationDefault(
                module: ModuleID(rawValue: "a"),
                identifier: "one"
            )
        ) {
            try host.register(assembly)
        }
    }

    @Test func documentationCannotReferenceUndeclaredThings() throws {
        let command = Fixture.definition("a.one")
        let assembly = TestAssembly(
            manifest: Fixture.manifest("a", commands: [command], articles: ["a.article"]),
            commandDefinitions: [command],
            documentation: ModuleDocumentationContribution(articles: [
                ModuleDocumentationArticle(
                    id: "a.article",
                    title: "A",
                    summary: "A",
                    references: [.command(CommandID(rawValue: "b.unknown"))]
                )
            ])
        )
        let host = ModuleHost()
        #expect(
            throws: ModuleHostError.danglingDocumentationReference(
                module: ModuleID(rawValue: "a"),
                article: "a.article"
            )
        ) {
            try host.register(assembly)
        }
    }

    @Test func manifestArticleWithoutContributionIsRejected() throws {
        let command = Fixture.definition("a.one")
        let assembly = TestAssembly(
            manifest: Fixture.manifest("a", commands: [command], articles: ["a.missing"]),
            commandDefinitions: [command]
        )
        let host = ModuleHost()
        #expect(
            throws: ModuleHostError.missingDocumentationArticle(
                module: ModuleID(rawValue: "a"),
                identifier: "a.missing"
            )
        ) {
            try host.register(assembly)
        }
    }
}

// MARK: - Activation

@MainActor
struct ModuleHostActivationTests {
    @Test func concurrentActivationHappensExactlyOnce() async throws {
        let counter = ActivationCounter()
        let host = ModuleHost()
        try host.register(
            Fixture.assembly("a", commandIDs: ["a.one", "a.two"], counter: counter)
        )

        async let first = host.handler(for: CommandID(rawValue: "a.one"))
        async let second = host.handler(for: CommandID(rawValue: "a.two"))
        async let third = host.activate(ModuleID(rawValue: "a"))
        _ = try await (first, second, third)

        #expect(counter.activationCount == 1)
        #expect(counter.lifecycleStarts == 1)
    }

    @Test func repeatedActivationCyclesDoNotDuplicateMonitors() async throws {
        let counter = ActivationCounter()
        let host = ModuleHost()
        try host.register(Fixture.assembly("a", commandIDs: ["a.one"], counter: counter))

        for _ in 0 ..< 3 {
            _ = try await host.activate(ModuleID(rawValue: "a"))
            #expect(await host.deactivate(ModuleID(rawValue: "a")))
        }

        #expect(counter.activationCount == 3)
        #expect(counter.lifecycleStarts == 3)
        #expect(counter.lifecycleStops == 3)
        #expect(host.isActivated(ModuleID(rawValue: "a")) == false)
    }

    @Test func blockedDeactivationLeavesTheModuleRunning() async throws {
        let counter = ActivationCounter()
        let host = ModuleHost()
        try host.register(
            Fixture.assembly(
                "a",
                commandIDs: ["a.one"],
                counter: counter,
                deactivationDecision: .block(reason: "Unsaved work")
            )
        )
        _ = try await host.activate(ModuleID(rawValue: "a"))

        #expect(await host.deactivate(ModuleID(rawValue: "a")) == false)
        #expect(counter.lifecycleStops == 0)
        #expect(host.isActivated(ModuleID(rawValue: "a")))
    }

    @Test func unknownCommandIsRejected() async {
        let host = ModuleHost()
        await #expect(throws: ModuleHostError.unknownCommand(CommandID(rawValue: "nope"))) {
            _ = try await host.handler(for: CommandID(rawValue: "nope"))
        }
    }

    @Test func activationFailureIsIsolatedAndReported() async throws {
        struct Boom: Error {}
        let command = Fixture.definition("a.one")
        let host = ModuleHost()
        try host.register(
            TestAssembly(
                manifest: Fixture.manifest("a", commands: [command]),
                commandDefinitions: [command],
                activationError: Boom()
            )
        )
        try host.register(Fixture.assembly("b", commandIDs: ["b.one"]))

        await #expect(throws: (any Error).self) {
            _ = try await host.handler(for: CommandID(rawValue: "a.one"))
        }
        // The failed module reports availability; the healthy one still works.
        if case .failed = host.availability(of: ModuleID(rawValue: "a")) {} else {
            Issue.record("Expected the failed module to report .failed availability.")
        }
        let handler = try await host.handler(for: CommandID(rawValue: "b.one"))
        let outcome = await handler.execute(
            ModuleCommandInvocation(
                commandID: CommandID(rawValue: "b.one"),
                arguments: .empty,
                context: CommandInvocationContext(source: .search),
                grants: .directUser
            )
        )
        #expect(outcome.didCompleteEffect)
    }

    @Test func launchModulesStartOnlyWhenEnabledAndPolicyAsks() async throws {
        let launchCounter = ActivationCounter()
        let onDemandCounter = ActivationCounter()
        let disabledCounter = ActivationCounter()
        let enablement = ToggleableEnablement()
        enablement.disabled = [ModuleID(rawValue: "disabled")]
        let host = ModuleHost(enablement: enablement)

        try host.register(
            Fixture.assembly(
                "launch", commandIDs: ["launch.one"],
                counter: launchCounter, policy: .atLaunchWhenEnabled
            )
        )
        try host.register(
            Fixture.assembly("ondemand", commandIDs: ["ondemand.one"], counter: onDemandCounter)
        )
        try host.register(
            Fixture.assembly(
                "disabled", commandIDs: ["disabled.one"],
                counter: disabledCounter, policy: .atLaunchWhenEnabled
            )
        )

        await host.activateLaunchModules()

        #expect(launchCounter.activationCount == 1)
        #expect(onDemandCounter.activationCount == 0)
        #expect(disabledCounter.activationCount == 0)
    }
}

// MARK: - Ownership and cleanup

@MainActor
struct ModuleHostOwnershipTests {
    @Test func staleTokenCannotUnregisterAReplacement() async throws {
        let host = ModuleHost()
        let firstToken = try host.register(Fixture.assembly("a", commandIDs: ["a.one"]))
        #expect(await host.unregister(firstToken))

        let secondToken = try host.register(Fixture.assembly("a", commandIDs: ["a.one"]))
        // The superseded token must not remove the live registration.
        #expect(await host.unregister(firstToken) == false)
        #expect(host.commandDefinitions().map(\.id.rawValue) == ["a.one"])
        #expect(await host.unregister(secondToken))
        #expect(host.commandDefinitions().isEmpty)
    }

    @Test func unregisterReleasesRetainedBehavior() async throws {
        let counter = ActivationCounter()
        let host = ModuleHost()
        let token = try host.register(
            Fixture.assembly("a", commandIDs: ["a.one"], counter: counter)
        )
        _ = try await host.activate(ModuleID(rawValue: "a"))

        #expect(await host.unregister(token))
        #expect(counter.lifecycleStops == 1)
        #expect(host.owningModuleID(of: CommandID(rawValue: "a.one")) == nil)
    }

    @Test func deactivateAllReleasesEveryActivatedModule() async throws {
        let first = ActivationCounter()
        let second = ActivationCounter()
        let host = ModuleHost()
        try host.register(Fixture.assembly("a", commandIDs: ["a.one"], counter: first))
        try host.register(Fixture.assembly("b", commandIDs: ["b.one"], counter: second))
        _ = try await host.activate(ModuleID(rawValue: "a"))
        _ = try await host.activate(ModuleID(rawValue: "b"))

        await host.deactivateAll()

        #expect(first.lifecycleStops == 1)
        #expect(second.lifecycleStops == 1)
    }
}

// MARK: - Availability

@MainActor
struct ModuleHostAvailabilityTests {
    @Test func disabledModuleReportsDisabled() throws {
        let enablement = ToggleableEnablement()
        enablement.disabled = [ModuleID(rawValue: "a")]
        let host = ModuleHost(enablement: enablement)
        try host.register(Fixture.assembly("a", commandIDs: ["a.one"]))

        #expect(host.availability(of: ModuleID(rawValue: "a")) == .disabled)
        #expect(host.availability(ofCommand: CommandID(rawValue: "a.one")) == .disabled)
    }

    @Test func gatedModuleIsNeverAvailable() throws {
        let host = ModuleHost()
        try host.register(Fixture.assembly("a", commandIDs: ["a.one"], status: .gated))
        #expect(host.availability(of: ModuleID(rawValue: "a")).isAvailable == false)
    }

    @Test func unmetPermissionIsReportedWithoutPrompting() throws {
        let evaluator = StubCapabilityEvaluator()
        evaluator.unmet = .permission(identifier: "screen-recording")
        let host = ModuleHost(capabilities: evaluator)
        try host.register(
            Fixture.assembly(
                "a", commandIDs: ["a.one"],
                capabilities: [.permission(identifier: "screen-recording")]
            )
        )

        #expect(
            host.availability(of: ModuleID(rawValue: "a"))
                == .permissionRequired(identifier: "screen-recording")
        )
        // Availability is metadata: it must never have activated the module.
        #expect(host.isActivated(ModuleID(rawValue: "a")) == false)
    }

    @Test func missingConnectionIsReportedAsDisconnected() throws {
        let evaluator = StubCapabilityEvaluator()
        evaluator.unmet = .accountConnection(identifier: "notion")
        let host = ModuleHost(capabilities: evaluator)
        try host.register(
            Fixture.assembly(
                "a", commandIDs: ["a.one"],
                capabilities: [.accountConnection(identifier: "notion")]
            )
        )
        #expect(
            host.availability(of: ModuleID(rawValue: "a"))
                == .disconnected(identifier: "notion")
        )
    }
}

// MARK: - Lazy discovery

@MainActor
struct ModuleHostLazinessTests {
    @Test func settingsAndDocumentationDiscoveryDoesNotActivate() async throws {
        let counter = ActivationCounter()
        let command = Fixture.definition("a.one")
        let host = ModuleHost()
        try host.register(
            TestAssembly(
                manifest: Fixture.manifest("a", commands: [command], articles: ["a.article"]),
                commandDefinitions: [command],
                settings: ModuleSettingsContribution(fields: [
                    ModuleConfigurationField(
                        id: "one", variable: "one", title: "One",
                        kind: .toggle, defaultValue: .boolean(true)
                    )
                ]),
                documentation: ModuleDocumentationContribution(articles: [
                    ModuleDocumentationArticle(
                        id: "a.article", title: "A", summary: "A",
                        references: [.command(command.id), .setting(variable: "one")]
                    )
                ]),
                counter: counter
            )
        )

        #expect(host.settingsContributions().count == 1)
        #expect(host.documentationContributions().count == 1)
        #expect(host.commandDefinitions().count == 1)
        #expect(counter.activationCount == 0)
        #expect(counter.lifecycleStarts == 0)
    }

    @Test func disabledModulesStayDiscoverableInSettingsAndDocs() throws {
        let enablement = ToggleableEnablement()
        enablement.disabled = [ModuleID(rawValue: "a")]
        let command = Fixture.definition("a.one")
        let host = ModuleHost(enablement: enablement)
        try host.register(
            TestAssembly(
                manifest: Fixture.manifest("a", commands: [command]),
                commandDefinitions: [command],
                settings: ModuleSettingsContribution(fields: [
                    ModuleConfigurationField(
                        id: "one", variable: "one", title: "One",
                        kind: .toggle, defaultValue: .boolean(true)
                    )
                ])
            )
        )

        #expect(host.availability(of: ModuleID(rawValue: "a")) == .disabled)
        #expect(host.settingsContributions().count == 1)
    }
}
