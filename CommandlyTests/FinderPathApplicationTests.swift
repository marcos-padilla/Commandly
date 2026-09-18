import CommandKit
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct FinderPathApplicationTests {
    @Test func registeredEntriesAndDirectLaunchDoNotActivateNativeServices() async throws {
        let reader = FinderApplicationTestReader(); let copier = FinderApplicationTestCopier()
        let app = FinderPathApplication(services: .init(reader: reader, copier: copier, openSettings: {}))
        #expect(app.definition.id == FinderPathApplication.id)
        #expect(app.definition.documentation != nil)
        #expect(app.toolDefinitions.map(\.id) == [FinderPathApplication.copyToolID])
        guard case .present(let session) = app.launch(in: context()) else { Issue.record("Expected Finder Path UI"); return }
        let model = try #require(session.model(as: FinderPathViewModel.self)); model.activate()
        #expect(await reader.calls == 0)
        guard case .present = app.launch(toolID: FinderPathApplication.copyToolID, arguments: .init(), in: context()) else {
            Issue.record("Expected consent-capable tool UI"); return
        }
        #expect(await reader.calls == 0) // Surface task, not registry construction, starts the explicit tool.
        session.stop()
    }
    @Test func disabledUnknownAndArgumentBearingInvocationsFailClosed() async {
        let reader = FinderApplicationTestReader()
        let app = FinderPathApplication(services: .init(reader: reader, copier: FinderApplicationTestCopier(), openSettings: {}))
        guard case .message = app.launch(in: context(enabled: false)),
              case .message = app.launch(toolID: .init(rawValue: "unknown"), arguments: .init(), in: context()),
              case .message = app.launch(toolID: FinderPathApplication.copyToolID, arguments: .init(["path": .string("/generated/ignored")]), in: context()) else {
            Issue.record("Unsafe invocation should not launch"); return
        }
        #expect(await reader.calls == 0)
    }
    @Test func generatedFixtureUsesExplicitConsentFlowAndCopiesOnlyLabeledGeneratedText() async throws {
        let copier = FinderApplicationTestCopier()
        let model = FinderPathViewModel(services: FinderPathDebugFixture.services(copier: copier), onGoBack: {})
        #expect(model.fixtureLabel?.contains("Generated UI fixture") == true)
        model.activate(copyImmediately: true); await model.flushForTesting()
        #expect(model.needsConsent); #expect(copier.paths.isEmpty)
        model.performPrimary(); await model.flushForTesting()
        #expect(copier.paths == ["/Generated Commandly Fixture/Example.txt"])
        model.stop()
    }
    private func context(enabled: Bool = true) -> LauncherApplicationContext {
        .init(navigation: .init(dismissLauncher: {}, openSettings: {}, goBack: {}),
              settings: .init(alias: "", hotKey: nil, isEnabled: enabled, configuration: [:]))
    }
}
private actor FinderApplicationTestReader: FinderPathReading {
    private(set) var calls = 0
    func authorization(allowPrompt: Bool) -> FinderPathAuthorization { calls += 1; return .requiresConsent }
    func capture() throws -> FinderPathSnapshot { calls += 1; throw FinderPathError.unavailable }
    func validate(_ snapshot: FinderPathSnapshot) throws { calls += 1; throw FinderPathError.unavailable }
}
@MainActor private final class FinderApplicationTestCopier: FinderPathCopying {
    var paths: [String] = []
    func copy(_ path: String) { paths.append(path) }
}
