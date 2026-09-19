import CommandKit
import Foundation
import Infrastructure
import ModuleKit
import ModuleRuntime
import Testing
@testable import ClipboardToolsModule

// MARK: - Test doubles

/// Pasteboard double that records writes and clears.
///
/// Locked rather than actor-isolated so tests can assert synchronously.
final class FakePasteboard: PasteboardAccessing, PasteboardClearing, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private(set) var clearCount = 0
    private(set) var writeCount = 0

    init(initial: String? = nil) { self.value = initial }

    func readString() async -> String? { lock.withLock { value } }

    func writeString(_ string: String) async {
        lock.withLock {
            value = string
            writeCount += 1
        }
    }

    func writeFileURLs(_ urls: [URL]) async { _ = urls }

    func clear() async {
        lock.withLock {
            value = nil
            clearCount += 1
        }
    }

    var current: String? { lock.withLock { value } }
}

@MainActor
final class ControllableEventObserver: ClipboardAutoClearEventObserving {
    private var handler: (@MainActor (ClipboardAutoClearTrigger) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(handler: @escaping @MainActor (ClipboardAutoClearTrigger) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    var isObserving: Bool { handler != nil }

    func emit(_ trigger: ClipboardAutoClearTrigger) { handler?(trigger) }
}

@MainActor
enum Fixture {
    static func invocation(
        _ commandID: CommandID,
        grants: ModuleCallerGrants = .directUser
    ) -> ModuleCommandInvocation {
        ModuleCommandInvocation(
            commandID: commandID,
            arguments: .empty,
            context: CommandInvocationContext(source: .search),
            grants: grants
        )
    }

    static func operations(_ pasteboard: FakePasteboard, extra: [String] = []) -> ClipboardToolsOperations {
        ClipboardToolsOperations(
            pasteboard: pasteboard,
            clearing: pasteboard,
            makeCleaner: { TrackingParameterCleaner(additionalParameterNames: extra) }
        )
    }
}

// MARK: - URL cleaning

struct TrackingParameterCleanerTests {
    private let cleaner = TrackingParameterCleaner()

    @Test func removesUTMParametersAndKeepsTheRest() throws {
        let cleaned = try #require(
            cleaner.clean("https://example.com/post?id=42&utm_source=news&utm_medium=email")
        )
        #expect(cleaned == "https://example.com/post?id=42")
    }

    @Test func dropsTheQuestionMarkWhenEveryParameterGoes() throws {
        let cleaned = try #require(cleaner.clean("https://example.com/a?utm_source=x&fbclid=y"))
        #expect(cleaned == "https://example.com/a")
    }

    @Test func matchesParameterNamesCaseInsensitively() throws {
        let cleaned = try #require(cleaner.clean("https://example.com/a?UTM_Source=x&keep=1"))
        #expect(cleaned == "https://example.com/a?keep=1")
    }

    @Test func preservesFragmentPathAndPort() throws {
        let cleaned = try #require(
            cleaner.clean("https://example.com:8443/a/b?gclid=1&q=swift#section")
        )
        #expect(cleaned == "https://example.com:8443/a/b?q=swift#section")
    }

    @Test func preservesRemainingParameterOrder() throws {
        let cleaned = try #require(
            cleaner.clean("https://example.com/a?z=1&utm_source=x&a=2&b=3")
        )
        #expect(cleaned == "https://example.com/a?z=1&a=2&b=3")
    }

    @Test func leavesACleanLinkAlone() {
        #expect(cleaner.clean("https://example.com/a?q=swift") == nil)
    }

    @Test func leavesALinkWithoutAQueryAlone() {
        #expect(cleaner.clean("https://example.com/a") == nil)
    }

    @Test func ignoresTextThatIsNotASingleURL() {
        #expect(cleaner.clean("see https://example.com/a?utm_source=x for details") == nil)
        #expect(cleaner.clean("just some copied words") == nil)
        #expect(cleaner.clean("") == nil)
    }

    @Test func ignoresNonWebSchemes() {
        // Stripping parameters from a non-web URL risks breaking something we do not understand.
        #expect(cleaner.clean("mailto:someone@example.com?utm_source=x") == nil)
        #expect(cleaner.clean("file:///tmp/a?utm_source=x") == nil)
    }

    @Test func keepsUnknownParametersRatherThanGuessing() throws {
        // "ref" is genuinely load-bearing on some sites, so it is not stripped by default.
        let cleaned = try #require(cleaner.clean("https://example.com/a?ref=abc&utm_source=x"))
        #expect(cleaned == "https://example.com/a?ref=abc")
    }

    @Test func honoursExtraParameterNamesTheUserChose() throws {
        let custom = TrackingParameterCleaner(additionalParameterNames: ["ref", " SOURCE "])
        let cleaned = try #require(custom.clean("https://example.com/a?ref=abc&source=x&keep=1"))
        #expect(cleaned == "https://example.com/a?keep=1")
    }

    @Test func cleaningIsIdempotent() throws {
        let once = try #require(cleaner.clean("https://example.com/a?utm_source=x&keep=1"))
        #expect(cleaner.clean(once) == nil)
    }
}

// MARK: - Operations

@MainActor
struct ClipboardToolsOperationsTests {
    @Test func flattenRewritesTheClipboardText() async {
        let pasteboard = FakePasteboard(initial: "Hello")
        let didChange = await Fixture.operations(pasteboard).flattenToPlainText()
        #expect(didChange)
        #expect(pasteboard.current == "Hello")
        // The rewrite is what drops rich representations, so it must actually happen.
        #expect(pasteboard.writeCount == 1)
    }

    @Test func flattenReportsWhenThereIsNothingToDo() async {
        let pasteboard = FakePasteboard(initial: nil)
        let didChange = await Fixture.operations(pasteboard).flattenToPlainText()
        #expect(didChange == false)
        #expect(pasteboard.writeCount == 0)
    }

    @Test func cleanReportsHowManyParametersWereRemoved() async {
        let pasteboard = FakePasteboard(initial: "https://example.com/a?utm_source=x&gclid=y&keep=1")
        let removed = await Fixture.operations(pasteboard).cleanCopiedLink()
        #expect(removed == 2)
        #expect(pasteboard.current == "https://example.com/a?keep=1")
    }

    @Test func cleanLeavesANonLinkUntouched() async {
        let pasteboard = FakePasteboard(initial: "just some words")
        let removed = await Fixture.operations(pasteboard).cleanCopiedLink()
        #expect(removed == nil)
        #expect(pasteboard.writeCount == 0)
        #expect(pasteboard.current == "just some words")
    }

    @Test func clearEmptiesTheClipboard() async {
        let pasteboard = FakePasteboard(initial: "secret")
        await Fixture.operations(pasteboard).clearClipboard()
        #expect(pasteboard.current == nil)
        #expect(pasteboard.clearCount == 1)
    }
}

// MARK: - Command handlers

@MainActor
struct ClipboardToolsHandlerTests {
    @Test func everyHandlerDeniesAnUngrantedCallerWithoutEffect() async {
        let pasteboard = FakePasteboard(initial: "https://example.com/a?utm_source=x")
        let operations = Fixture.operations(pasteboard)
        let handlers: [(CommandID, any ModuleCommandHandling)] = [
            (ClipboardToolsIdentifiers.plainText, FlattenClipboardCommandHandler(operations: operations)),
            (ClipboardToolsIdentifiers.cleanURL, CleanCopiedLinkCommandHandler(operations: operations)),
            (ClipboardToolsIdentifiers.clearNow, ClearClipboardCommandHandler(operations: operations))
        ]

        for (id, handler) in handlers {
            let outcome = await handler.execute(Fixture.invocation(id, grants: []))
            guard case .denied = outcome else {
                Issue.record("Expected \(id.rawValue) to deny an ungranted caller. Got \(outcome).")
                continue
            }
        }
        #expect(pasteboard.writeCount == 0)
        #expect(pasteboard.clearCount == 0)
    }

    @Test func cleanHandlerReportsTheRemovedCount() async {
        let pasteboard = FakePasteboard(initial: "https://example.com/a?utm_source=x&keep=1")
        let handler = CleanCopiedLinkCommandHandler(operations: Fixture.operations(pasteboard))
        let outcome = await handler.execute(Fixture.invocation(ClipboardToolsIdentifiers.cleanURL))

        guard case .succeeded(_, let output) = outcome else {
            Issue.record("Expected success. Got \(outcome).")
            return
        }
        #expect(output[ClipboardToolsOutputName.removedParameterCount] == .integer(1))
    }

    @Test func cleanHandlerFailsHonestlyOnANonLink() async {
        let pasteboard = FakePasteboard(initial: "not a link")
        let handler = CleanCopiedLinkCommandHandler(operations: Fixture.operations(pasteboard))
        let outcome = await handler.execute(Fixture.invocation(ClipboardToolsIdentifiers.cleanURL))

        guard case .failed = outcome else {
            Issue.record("Expected an honest failure. Got \(outcome).")
            return
        }
        #expect(outcome.didCompleteEffect == false)
    }

    @Test func presentationCommandReportsInteractionRequired() async {
        let outcome = await ClipboardToolsPresentationHandler()
            .execute(Fixture.invocation(ClipboardToolsIdentifiers.application))
        guard case .interactionRequired = outcome else {
            Issue.record("Expected interactionRequired. Got \(outcome).")
            return
        }
    }
}

// MARK: - Auto-clear

@MainActor
struct ClipboardAutoClearTests {
    private func scheduler(
        _ pasteboard: FakePasteboard,
        observer: ControllableEventObserver,
        configuration: ClipboardAutoClearConfiguration,
        sleeper: @escaping ClipboardAutoClearScheduler.Sleeper = { _ in }
    ) -> ClipboardAutoClearScheduler {
        ClipboardAutoClearScheduler(
            pasteboard: pasteboard,
            observer: observer,
            configuration: configuration,
            sleeper: sleeper
        )
    }

    @Test func idleCountdownClearsAfterTheConfiguredDelay() async {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let scheduler = scheduler(
            pasteboard,
            observer: observer,
            configuration: .init(idleTimeoutSeconds: 30, triggers: [.idleTimeout])
        )

        scheduler.noteClipboardChanged()
        // The injected sleeper returns immediately, so the countdown resolves without real time.
        while scheduler.clearCount == 0 { await Task.yield() }

        #expect(pasteboard.current == nil)
        #expect(scheduler.lastTrigger == .idleTimeout)
    }

    @Test func aNewCopyReplacesThePendingCountdownInsteadOfStacking() async {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let scheduler = scheduler(
            pasteboard,
            observer: observer,
            configuration: .init(idleTimeoutSeconds: 30, triggers: [.idleTimeout])
        )

        for _ in 0 ..< 5 { scheduler.noteClipboardChanged() }
        while scheduler.clearCount == 0 { await Task.yield() }
        for _ in 0 ..< 50 { await Task.yield() }

        // Five copies must not queue five clears.
        #expect(scheduler.clearCount == 1)
    }

    @Test func noCountdownRunsWhenTheIdleTriggerIsOff() async {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let scheduler = scheduler(
            pasteboard,
            observer: observer,
            configuration: .init(idleTimeoutSeconds: 0, triggers: [])
        )

        scheduler.noteClipboardChanged()
        for _ in 0 ..< 50 { await Task.yield() }

        #expect(scheduler.clearCount == 0)
        #expect(pasteboard.current == "secret")
    }

    @Test func systemEventsClearOnlyWhenTheirTriggerIsEnabled() async {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let scheduler = scheduler(
            pasteboard,
            observer: observer,
            configuration: .init(idleTimeoutSeconds: 0, triggers: [.screenLock])
        )
        scheduler.start()

        observer.emit(.systemSleep)
        for _ in 0 ..< 20 { await Task.yield() }
        #expect(scheduler.clearCount == 0)

        observer.emit(.screenLock)
        while scheduler.clearCount == 0 { await Task.yield() }
        #expect(scheduler.lastTrigger == .screenLock)
    }

    @Test func observationStopsAndDoesNotDuplicateAcrossCycles() async {
        let pasteboard = FakePasteboard()
        let observer = ControllableEventObserver()
        let scheduler = scheduler(
            pasteboard,
            observer: observer,
            configuration: .init(idleTimeoutSeconds: 0, triggers: [.screenLock])
        )

        for _ in 0 ..< 3 {
            scheduler.start()
            scheduler.stop()
        }

        #expect(observer.startCount == 3)
        #expect(observer.stopCount == 3)
        #expect(observer.isObserving == false)
    }

    @Test func reapplyingTheSameConfigurationDoesNotRestartObservation() {
        let pasteboard = FakePasteboard()
        let observer = ControllableEventObserver()
        let configuration = ClipboardAutoClearConfiguration(
            idleTimeoutSeconds: 0,
            triggers: [.screenLock]
        )
        let scheduler = scheduler(pasteboard, observer: observer, configuration: configuration)
        scheduler.start()
        #expect(observer.startCount == 1)

        scheduler.apply(configuration)
        #expect(observer.startCount == 1)
    }

    @Test func turningEveryTriggerOffReleasesTheObserver() {
        let pasteboard = FakePasteboard()
        let observer = ControllableEventObserver()
        let scheduler = scheduler(
            pasteboard,
            observer: observer,
            configuration: .init(idleTimeoutSeconds: 0, triggers: [.screenLock])
        )
        scheduler.start()
        #expect(observer.isObserving)

        scheduler.apply(.disabled)
        #expect(observer.isObserving == false)
    }
}

// MARK: - Settings

struct ClipboardToolsSettingsTests {
    @Test func everythingIsOffByDefault() {
        let configuration = ClipboardToolsSettings.autoClearConfiguration(from: [:])
        #expect(configuration.isActive == false)
        #expect(configuration.triggers.isEmpty)
        #expect(ClipboardToolsSettings.cleansLinksAutomatically(from: [:]) == false)
    }

    @Test func idleSecondsAreClampedToTheDeclaredBounds() {
        let tooLarge = ClipboardToolsSettings.autoClearConfiguration(
            from: [ClipboardToolsSettingsVariable.autoClearIdleSeconds: .integer(Int.max)]
        )
        #expect(tooLarge.idleTimeoutSeconds == ClipboardToolsSettings.maximumIdleSeconds)

        let negative = ClipboardToolsSettings.autoClearConfiguration(
            from: [ClipboardToolsSettingsVariable.autoClearIdleSeconds: .integer(-30)]
        )
        #expect(negative.idleTimeoutSeconds == 0)
        #expect(negative.triggers.contains(.idleTimeout) == false)
    }

    @Test func extraParameterNamesAreParsedAndTrimmed() {
        let names = ClipboardToolsSettings.additionalTrackingParameters(
            from: [ClipboardToolsSettingsVariable.additionalTrackingParameters: .text(" ref, source ,, x ")]
        )
        #expect(names == ["ref", "source", "x"])
    }

    @Test func everyDeclaredFieldHasAMatchingSettingsVariable() {
        let declared = Set(ClipboardToolsSettings.contribution.fields.map(\.variable))
        #expect(declared.contains(ClipboardToolsSettingsVariable.cleanLinksAutomatically))
        #expect(declared.contains(ClipboardToolsSettingsVariable.additionalTrackingParameters))
        #expect(declared.contains(ClipboardToolsSettingsVariable.autoClearIdleSeconds))
        #expect(declared.contains(ClipboardToolsSettingsVariable.autoClearOnSystemSleep))
        #expect(declared.contains(ClipboardToolsSettingsVariable.autoClearOnDisplaySleep))
        #expect(declared.contains(ClipboardToolsSettingsVariable.autoClearOnScreenLock))
    }
}

// MARK: - Module policy and host integration

struct ClipboardToolsPolicyTests {
    @Test func noCommandIsExposedToAI() {
        // These commands read and rewrite whatever the user copied, which can be a password or a
        // private link. None is reviewed for AI exposure.
        #expect(ClipboardToolsCommands.all.allSatisfy { $0.policy.aiExposure == .hidden })
    }

    @Test func theThreeToolsAreDirectOperations() {
        for command in [
            ClipboardToolsCommands.plainText,
            ClipboardToolsCommands.cleanURL,
            ClipboardToolsCommands.clearNow
        ] {
            #expect(command.policy.executionMode == .direct)
            #expect(command.policy.effect == .localMutation)
            #expect(command.policy.disclosure == .none)
        }
    }

    @Test func manifestOwnsEveryDeclaredCommand() {
        #expect(
            Set(ClipboardToolsManifest.value.ownedCommandIDs)
                == Set(ClipboardToolsCommands.all.map(\.id))
        )
    }

    @Test func identifiersAreStable() {
        #expect(ClipboardToolsIdentifiers.application.rawValue == "clipboard.tools")
        #expect(ClipboardToolsIdentifiers.plainText.rawValue == "clipboard.tools.plain-text")
        #expect(ClipboardToolsIdentifiers.cleanURL.rawValue == "clipboard.tools.clean-url")
        #expect(ClipboardToolsIdentifiers.clearNow.rawValue == "clipboard.tools.clear")
    }
}

@MainActor
struct ClipboardToolsHostTests {
    private func assembly(
        _ pasteboard: FakePasteboard,
        configuration: StaticClipboardToolsConfiguration,
        observer: ControllableEventObserver
    ) -> ClipboardToolsAssembly {
        ClipboardToolsAssembly(
            pasteboard: pasteboard,
            clearing: pasteboard,
            configuration: configuration,
            makeObserver: { observer }
        )
    }

    @Test func theModuleRegistersAndValidates() throws {
        let host = ModuleHost()
        #expect(throws: Never.self) {
            try host.register(
                assembly(
                    FakePasteboard(),
                    configuration: StaticClipboardToolsConfiguration(),
                    observer: ControllableEventObserver()
                )
            )
        }
        #expect(host.commandDefinitions().count == ClipboardToolsCommands.all.count)
    }

    @Test func metadataDiscoveryStartsNoObserverAndTouchesNoClipboard() throws {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let host = ModuleHost()
        try host.register(
            assembly(pasteboard, configuration: StaticClipboardToolsConfiguration(), observer: observer)
        )

        _ = host.commandDefinitions()
        _ = host.settingsContributions()
        _ = host.documentationContributions()

        #expect(host.isActivated(ClipboardToolsIdentifiers.module) == false)
        #expect(observer.startCount == 0)
        #expect(pasteboard.current == "secret")
        #expect(pasteboard.clearCount == 0)
    }

    @Test func commandsAreDispatchableThroughTheHost() async throws {
        let pasteboard = FakePasteboard(initial: "https://example.com/a?utm_source=x")
        let host = ModuleHost()
        try host.register(
            assembly(
                pasteboard,
                configuration: StaticClipboardToolsConfiguration(),
                observer: ControllableEventObserver()
            )
        )

        let handler = try await host.handler(for: ClipboardToolsIdentifiers.cleanURL)
        let outcome = await handler.execute(Fixture.invocation(ClipboardToolsIdentifiers.cleanURL))

        #expect(outcome.didCompleteEffect)
        #expect(pasteboard.current == "https://example.com/a")
    }

    @Test func deactivationReleasesTheObserverWithoutClearingTheClipboard() async throws {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let configuration = StaticClipboardToolsConfiguration(
            values: [ClipboardToolsSettingsVariable.autoClearOnScreenLock: .boolean(true)]
        )
        let host = ModuleHost()
        try host.register(assembly(pasteboard, configuration: configuration, observer: observer))

        _ = try await host.activate(ClipboardToolsIdentifiers.module)
        #expect(observer.isObserving)

        #expect(await host.deactivate(ClipboardToolsIdentifiers.module))

        // Disabling the module stops its behavior. It must not clear what the user copied.
        #expect(observer.isObserving == false)
        #expect(pasteboard.current == "secret")
        #expect(pasteboard.clearCount == 0)
    }

    @Test func settingsChangesReachTheRunningScheduler() async throws {
        let pasteboard = FakePasteboard(initial: "secret")
        let observer = ControllableEventObserver()
        let configuration = StaticClipboardToolsConfiguration()
        let host = ModuleHost()
        try host.register(assembly(pasteboard, configuration: configuration, observer: observer))

        let activation = try await host.activate(ClipboardToolsIdentifiers.module)
        let lifecycle = try #require(activation.lifecycle as? ClipboardToolsLifecycle)
        #expect(observer.isObserving == false)

        configuration.update([ClipboardToolsSettingsVariable.autoClearOnScreenLock: .boolean(true)])
        lifecycle.configurationDidChange()

        #expect(observer.isObserving)
    }

    @Test func automaticLinkCleaningRunsOnlyWhenEnabled() async throws {
        let pasteboard = FakePasteboard(initial: "https://example.com/a?utm_source=x")
        let observer = ControllableEventObserver()
        let configuration = StaticClipboardToolsConfiguration()
        let host = ModuleHost()
        try host.register(assembly(pasteboard, configuration: configuration, observer: observer))

        let activation = try await host.activate(ClipboardToolsIdentifiers.module)
        let lifecycle = try #require(activation.lifecycle as? ClipboardToolsLifecycle)

        await lifecycle.clipboardDidChange()
        #expect(pasteboard.current == "https://example.com/a?utm_source=x")

        configuration.update([ClipboardToolsSettingsVariable.cleanLinksAutomatically: .boolean(true)])
        await lifecycle.clipboardDidChange()
        #expect(pasteboard.current == "https://example.com/a")
    }
}
