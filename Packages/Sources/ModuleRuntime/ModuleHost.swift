import CommandKit
import Foundation
import ModuleKit

/// Registration and validation failures raised by ``ModuleHost``.
///
/// Cases carry identifiers only. They never carry user content or underlying system error text.
public enum ModuleHostError: Error, Equatable, Sendable {
    /// Two modules claim the same module identifier.
    case duplicateModule(ModuleID)
    /// Two modules, or one module twice, claim the same command identifier.
    case duplicateCommand(CommandID)
    /// A command definition is not listed in the module manifest's owned command identifiers.
    case commandNotOwned(module: ModuleID, command: CommandID)
    /// A manifest lists an owned command that has no canonical definition.
    case missingCommandDefinition(module: ModuleID, command: CommandID)
    /// Configuration field identifiers or storage variables are not unique within a module.
    case duplicateConfigurationField(module: ModuleID, identifier: String)
    /// A configuration field's default value does not match its declared kind.
    case invalidConfigurationDefault(module: ModuleID, identifier: String)
    /// Documentation article identifiers are not unique within a module.
    case duplicateDocumentationArticle(module: ModuleID, identifier: String)
    /// Documentation references something the module does not declare.
    case danglingDocumentationReference(module: ModuleID, article: String)
    /// A module manifest declares articles that its documentation contribution does not provide.
    case missingDocumentationArticle(module: ModuleID, identifier: String)
    /// The module is not registered.
    case unknownModule(ModuleID)
    /// No registered module owns the command.
    case unknownCommand(CommandID)
    /// The module activated but bound no handler for one of its declared commands.
    case missingHandler(module: ModuleID, command: CommandID)
    /// Activation threw. The reason is a sanitized description supplied by the module.
    case activationFailed(module: ModuleID, reason: String)
}

/// Proof of ownership for one registration generation.
///
/// A token from a superseded registration cannot unregister its replacement: the host compares the
/// generation as well as the module identifier.
public struct ModuleRegistrationToken: Hashable, Sendable {
    /// Module this token registers.
    public let moduleID: ModuleID
    fileprivate let generation: UUID

    fileprivate init(moduleID: ModuleID, generation: UUID) {
        self.moduleID = moduleID
        self.generation = generation
    }
}

/// Supplies effective enablement for a module.
///
/// The host application backs this with its existing enablement store so that group and
/// application inheritance semantics are not duplicated.
@MainActor
public protocol ModuleEnablementProviding: AnyObject, Sendable {
    /// Whether the module is effectively enabled, including inherited settings.
    func isEnabled(_ moduleID: ModuleID) -> Bool
}

/// Evaluates a module's declared capability requirements without prompting the user.
@MainActor
public protocol ModuleCapabilityEvaluating: AnyObject, Sendable {
    /// Returns the first unmet requirement, or `nil` when all are satisfied.
    ///
    /// Implementations must read cached state only. Evaluating a capability must never present a
    /// system permission dialog or open a network connection.
    func firstUnmetRequirement(
        among requirements: [ModuleCapabilityRequirement]
    ) -> ModuleCapabilityRequirement?
}

/// Default evaluator used by tests and by hosts without capability wiring yet.
@MainActor
public final class AlwaysSatisfiedCapabilityEvaluator: ModuleCapabilityEvaluating {
    public init() {}

    public func firstUnmetRequirement(
        among requirements: [ModuleCapabilityRequirement]
    ) -> ModuleCapabilityRequirement? {
        _ = requirements
        return nil
    }
}

/// Enablement provider that reports every module as enabled.
@MainActor
public final class AlwaysEnabledModuleEnablementProvider: ModuleEnablementProviding {
    public init() {}

    public func isEnabled(_ moduleID: ModuleID) -> Bool {
        _ = moduleID
        return true
    }
}

/// Generic host for feature modules.
///
/// The host owns registration validation, deterministic catalog projection, lazy exactly-once
/// activation, ownership-scoped cleanup, and availability. It knows nothing about any concrete
/// feature and imports no feature target.
///
/// It is not a service locator: ``handler(for:)`` resolves only commands a module declared, and
/// there is no API to fetch a module's internal services.
@MainActor
public final class ModuleHost {
    private struct Entry {
        let assembly: any ModuleAssembly
        let generation: UUID
        let registrationOrder: Int
        var activation: Task<ModuleActivation, any Error>?
        var didStartLifecycle: Bool
        var failureReason: String?
    }

    private var entries: [ModuleID: Entry] = [:]
    private var moduleIDByCommandID: [CommandID: ModuleID] = [:]
    private var nextRegistrationOrder = 0

    private let enablement: any ModuleEnablementProviding
    private let capabilities: any ModuleCapabilityEvaluating

    /// Creates a module host.
    ///
    /// - Parameters:
    ///   - enablement: effective enablement source, including inherited settings.
    ///   - capabilities: cached capability evaluation. Must not prompt the user.
    public init(
        enablement: any ModuleEnablementProviding = AlwaysEnabledModuleEnablementProvider(),
        capabilities: any ModuleCapabilityEvaluating = AlwaysSatisfiedCapabilityEvaluator()
    ) {
        self.enablement = enablement
        self.capabilities = capabilities
    }

    // MARK: - Registration

    /// Validates and registers a module assembly without activating it.
    ///
    /// Registration reads metadata only. No service is constructed and no permission is requested.
    @discardableResult
    public func register(_ assembly: any ModuleAssembly) throws -> ModuleRegistrationToken {
        let manifest = assembly.manifest
        guard entries[manifest.id] == nil else {
            throw ModuleHostError.duplicateModule(manifest.id)
        }
        try validate(assembly)

        let generation = UUID()
        entries[manifest.id] = Entry(
            assembly: assembly,
            generation: generation,
            registrationOrder: nextRegistrationOrder,
            activation: nil,
            didStartLifecycle: false,
            failureReason: nil
        )
        nextRegistrationOrder += 1
        for definition in assembly.commandDefinitions {
            moduleIDByCommandID[definition.id] = manifest.id
        }
        return ModuleRegistrationToken(moduleID: manifest.id, generation: generation)
    }

    /// Removes a module registered with this exact token and releases everything it owns.
    ///
    /// A token whose generation no longer matches is ignored, so a superseded registration cannot
    /// unregister its replacement.
    @discardableResult
    public func unregister(_ token: ModuleRegistrationToken) async -> Bool {
        guard let entry = entries[token.moduleID], entry.generation == token.generation else {
            return false
        }
        await teardown(moduleID: token.moduleID)
        entries[token.moduleID] = nil
        for (commandID, owner) in moduleIDByCommandID where owner == token.moduleID {
            moduleIDByCommandID[commandID] = nil
        }
        return true
    }

    // MARK: - Catalog projection

    /// Registered module manifests in deterministic registration order.
    public func manifests() -> [ModuleManifest] {
        orderedEntries().map { $0.assembly.manifest }
    }

    /// Every declared command definition, in deterministic module-then-command order.
    ///
    /// This projection never activates a module.
    public func commandDefinitions() -> [ModuleCommandDefinition] {
        orderedEntries().flatMap { entry in
            entry.assembly.commandDefinitions.sorted { $0.id.rawValue < $1.id.rawValue }
        }
    }

    /// The canonical definition for a command, if a registered module declares it.
    public func commandDefinition(for commandID: CommandID) -> ModuleCommandDefinition? {
        guard let moduleID = moduleIDByCommandID[commandID],
              let entry = entries[moduleID] else {
            return nil
        }
        return entry.assembly.commandDefinitions.first { $0.id == commandID }
    }

    /// The module that owns a command, if any.
    public func owningModuleID(of commandID: CommandID) -> ModuleID? {
        moduleIDByCommandID[commandID]
    }

    /// Settings contributions in deterministic order, including disabled modules.
    public func settingsContributions() -> [(module: ModuleManifest, settings: ModuleSettingsContribution)] {
        orderedEntries().compactMap { entry in
            entry.assembly.settings.map { (entry.assembly.manifest, $0) }
        }
    }

    /// Documentation contributions in deterministic order, including disabled modules.
    public func documentationContributions() -> [(module: ModuleManifest, documentation: ModuleDocumentationContribution)] {
        orderedEntries().compactMap { entry in
            entry.assembly.documentation.map { (entry.assembly.manifest, $0) }
        }
    }

    // MARK: - Availability

    /// Current availability of a module.
    ///
    /// Evaluating availability reads cached enablement and capability state only.
    public func availability(of moduleID: ModuleID) -> ModuleAvailability {
        guard let entry = entries[moduleID] else {
            return .unsupported(reason: "Module is not registered.")
        }
        if let failureReason = entry.failureReason {
            return .failed(reason: failureReason)
        }
        if entry.assembly.manifest.status == .gated {
            return .unsupported(reason: "Module is not available in this build.")
        }
        guard enablement.isEnabled(moduleID) else {
            return .disabled
        }
        if let unmet = capabilities.firstUnmetRequirement(
            among: entry.assembly.manifest.capabilities
        ) {
            switch unmet {
            case .permission(let identifier):
                return .permissionRequired(identifier: identifier)
            case .accountConnection(let identifier), .helper(let identifier):
                return .disconnected(identifier: identifier)
            case .folderAccess(let identifier):
                return .permissionRequired(identifier: identifier)
            }
        }
        return .available
    }

    /// Current availability of a command, derived from its owning module.
    public func availability(ofCommand commandID: CommandID) -> ModuleAvailability {
        guard let moduleID = moduleIDByCommandID[commandID] else {
            return .unsupported(reason: "Command is not registered.")
        }
        return availability(of: moduleID)
    }

    /// Whether a module's services have been constructed.
    public func isActivated(_ moduleID: ModuleID) -> Bool {
        entries[moduleID]?.activation != nil
    }

    // MARK: - Activation

    /// Activates a module exactly once, even under concurrent requests.
    ///
    /// Concurrent callers await the same activation task, so a module's services are constructed a
    /// single time per registration generation. Service construction *and* lifecycle start both
    /// happen inside that one task, so every awaiter observes a module that is fully started — a
    /// caller can never receive a handler for a module whose retained behavior has not begun.
    @discardableResult
    public func activate(_ moduleID: ModuleID) async throws -> ModuleActivation {
        guard let entry = entries[moduleID] else {
            throw ModuleHostError.unknownModule(moduleID)
        }
        if let existing = entry.activation {
            return try await existing.value
        }

        let assembly = entry.assembly
        let generation = entry.generation
        let task = Task<ModuleActivation, any Error> { @MainActor in
            let activation: ModuleActivation
            do {
                activation = try await assembly.activate()
            } catch {
                // The underlying error is deliberately not propagated: it may carry paths,
                // credentials, or other private detail from a feature's own services.
                throw ModuleHostError.activationFailed(
                    module: moduleID,
                    reason: "Module services could not be created."
                )
            }
            for definition in assembly.commandDefinitions
            where definition.policy.executionMode == .direct
                || definition.policy.executionMode == .longRunning {
                guard activation.handlers[definition.id] != nil else {
                    throw ModuleHostError.missingHandler(
                        module: moduleID,
                        command: definition.id
                    )
                }
            }
            if let lifecycle = activation.lifecycle {
                do {
                    try await lifecycle.activate()
                } catch {
                    // A partially started module must not be left holding resources.
                    await lifecycle.deactivate()
                    throw ModuleHostError.activationFailed(
                        module: moduleID,
                        reason: "Module services could not be started."
                    )
                }
            }
            return activation
        }
        entries[moduleID]?.activation = task

        do {
            let activation = try await task.value
            // A concurrent unregister/re-register may have replaced this entry while we awaited.
            guard let current = entries[moduleID], current.generation == generation else {
                await activation.lifecycle?.deactivate()
                throw ModuleHostError.unknownModule(moduleID)
            }
            if activation.lifecycle != nil, current.didStartLifecycle == false {
                entries[moduleID]?.didStartLifecycle = true
            }
            return activation
        } catch {
            if entries[moduleID]?.generation == generation {
                entries[moduleID]?.activation = nil
                if entries[moduleID]?.failureReason == nil {
                    entries[moduleID]?.failureReason = "Module could not be activated."
                }
            }
            throw error
        }
    }

    /// Starts modules whose activation policy is ``ModuleActivationPolicy/atLaunchWhenEnabled``.
    ///
    /// Modules that fail are isolated: their failure is recorded as availability and the remaining
    /// modules still start.
    public func activateLaunchModules() async {
        for entry in orderedEntries()
        where entry.assembly.manifest.activationPolicy == .atLaunchWhenEnabled {
            let moduleID = entry.assembly.manifest.id
            guard availability(of: moduleID).isAvailable else { continue }
            _ = try? await activate(moduleID)
        }
    }

    /// Resolves the handler for a command, activating its module on first use.
    ///
    /// - Throws: ``ModuleHostError/unknownCommand(_:)`` when no module declares the command, or
    ///   ``ModuleHostError/missingHandler(module:command:)`` when the module bound no handler.
    public func handler(for commandID: CommandID) async throws -> any ModuleCommandHandling {
        guard let moduleID = moduleIDByCommandID[commandID] else {
            throw ModuleHostError.unknownCommand(commandID)
        }
        let activation = try await activate(moduleID)
        guard let handler = activation.handlers[commandID] else {
            throw ModuleHostError.missingHandler(module: moduleID, command: commandID)
        }
        return handler
    }

    // MARK: - Deactivation

    /// Asks a module whether it may be deactivated, without changing any state.
    public func prepareForDeactivation(_ moduleID: ModuleID) async -> ModuleDeactivationDecision {
        guard let entry = entries[moduleID], let task = entry.activation else { return .allow }
        guard let activation = try? await task.value, let lifecycle = activation.lifecycle else {
            return .allow
        }
        return await lifecycle.prepareForDeactivation()
    }

    /// Deactivates a module after confirming it allows the transition.
    ///
    /// Returns `false` when the module blocked the transition; in that case nothing is torn down
    /// and the module keeps its previous state.
    @discardableResult
    public func deactivate(_ moduleID: ModuleID) async -> Bool {
        guard entries[moduleID] != nil else { return false }
        if case .block = await prepareForDeactivation(moduleID) {
            return false
        }
        await teardown(moduleID: moduleID)
        return true
    }

    /// Releases every activated module. Used during application shutdown.
    public func deactivateAll() async {
        for entry in orderedEntries() {
            await teardown(moduleID: entry.assembly.manifest.id)
        }
    }

    private func teardown(moduleID: ModuleID) async {
        guard let entry = entries[moduleID], let task = entry.activation else { return }
        entries[moduleID]?.activation = nil
        entries[moduleID]?.didStartLifecycle = false
        guard let activation = try? await task.value else { return }
        await activation.lifecycle?.deactivate()
    }

    // MARK: - Validation

    private func orderedEntries() -> [Entry] {
        entries.values.sorted { $0.registrationOrder < $1.registrationOrder }
    }

    private func validate(_ assembly: any ModuleAssembly) throws {
        let manifest = assembly.manifest
        let definitions = assembly.commandDefinitions

        var seenCommands: Set<CommandID> = []
        let ownedCommands = Set(manifest.ownedCommandIDs)
        for definition in definitions {
            guard seenCommands.insert(definition.id).inserted else {
                throw ModuleHostError.duplicateCommand(definition.id)
            }
            guard moduleIDByCommandID[definition.id] == nil else {
                throw ModuleHostError.duplicateCommand(definition.id)
            }
            guard ownedCommands.contains(definition.id) else {
                throw ModuleHostError.commandNotOwned(
                    module: manifest.id,
                    command: definition.id
                )
            }
        }
        for owned in manifest.ownedCommandIDs where seenCommands.contains(owned) == false {
            throw ModuleHostError.missingCommandDefinition(module: manifest.id, command: owned)
        }

        var settingVariables: Set<String> = []
        if let settings = assembly.settings {
            var fieldIdentifiers: Set<String> = []
            for field in settings.fields {
                guard fieldIdentifiers.insert(field.id).inserted else {
                    throw ModuleHostError.duplicateConfigurationField(
                        module: manifest.id,
                        identifier: field.id
                    )
                }
                guard field.variable.isEmpty == false,
                      settingVariables.insert(field.variable).inserted else {
                    throw ModuleHostError.duplicateConfigurationField(
                        module: manifest.id,
                        identifier: field.variable
                    )
                }
                guard field.kind.accepts(field.defaultValue) else {
                    throw ModuleHostError.invalidConfigurationDefault(
                        module: manifest.id,
                        identifier: field.id
                    )
                }
                if field.kind == .selection {
                    guard let selection = field.defaultValue.textValue,
                          field.options.contains(where: { $0.id == selection }) else {
                        throw ModuleHostError.invalidConfigurationDefault(
                            module: manifest.id,
                            identifier: field.id
                        )
                    }
                }
            }
        }

        let capabilityIdentifiers = Set(manifest.capabilities.map(Self.capabilityIdentifier))
        var articleIdentifiers: Set<String> = []
        if let documentation = assembly.documentation {
            for article in documentation.articles {
                guard articleIdentifiers.insert(article.id).inserted else {
                    throw ModuleHostError.duplicateDocumentationArticle(
                        module: manifest.id,
                        identifier: article.id
                    )
                }
                for reference in article.references {
                    let isValid: Bool
                    switch reference {
                    case .command(let commandID):
                        isValid = seenCommands.contains(commandID)
                    case .setting(let variable):
                        isValid = settingVariables.contains(variable)
                    case .capability(let identifier):
                        isValid = capabilityIdentifiers.contains(identifier)
                    }
                    guard isValid else {
                        throw ModuleHostError.danglingDocumentationReference(
                            module: manifest.id,
                            article: article.id
                        )
                    }
                }
            }
        }
        for declared in manifest.documentationArticleIDs
        where articleIdentifiers.contains(declared) == false {
            throw ModuleHostError.missingDocumentationArticle(
                module: manifest.id,
                identifier: declared
            )
        }
    }

    private static func capabilityIdentifier(
        _ requirement: ModuleCapabilityRequirement
    ) -> String {
        switch requirement {
        case .permission(let identifier),
             .accountConnection(let identifier),
             .folderAccess(let identifier),
             .helper(let identifier):
            return identifier
        }
    }
}
