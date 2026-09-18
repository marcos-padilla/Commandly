import CommandKit
import Infrastructure
import Testing
@testable import Commandly

@Suite("Screen recording launcher registration")
@MainActor
struct ScreenRecordingRegistrationTests {
    @Test
    func catalogRegistersApplicationAndAllThreeTools() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        for id in [ScreenRecordingApplication.id, ScreenRecordingApplication.windowToolID,
                   ScreenRecordingApplication.displayToolID, ScreenRecordingApplication.stopToolID] {
            #expect(registry.definition(for: id) != nil)
        }
    }

    @Test
    func explicitWindowToolDismissesLauncherBeforeOpeningSettingsWithoutCapture() {
        let presenter = RecordingPresenterDouble()
        let app = ScreenRecordingApplication(presenter: presenter)
        _ = app.launch(toolID: ScreenRecordingApplication.windowToolID, arguments: CommandArguments(),
                       in: context(presenter))
        #expect(presenter.events == ["dismiss", "present"])
        #expect(presenter.source == .window)
        #expect(presenter.stopCalls == 0)
    }

    @Test
    func stopDoesNothingWithoutSessionAndRoutesToRetainedSessionWhenActive() {
        let presenter = RecordingPresenterDouble()
        let app = ScreenRecordingApplication(presenter: presenter)
        _ = app.launch(toolID: ScreenRecordingApplication.stopToolID, arguments: CommandArguments(),
                       in: context(presenter))
        #expect(presenter.events.isEmpty)
        presenter.hasActiveOrUnsavedRecording = true
        _ = app.launch(toolID: ScreenRecordingApplication.stopToolID, arguments: CommandArguments(),
                       in: context(presenter))
        #expect(presenter.events == ["dismiss", "stop"])
        #expect(presenter.stopCalls == 1)
    }

    private func context(_ presenter: RecordingPresenterDouble) -> LauncherApplicationContext {
        LauncherApplicationContext(navigation: LauncherApplicationNavigation(
            dismissLauncher: { presenter.events.append("dismiss") }, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
    }
}

@MainActor
private final class RecordingPresenterDouble: ScreenRecordingPresenting {
    var hasActiveOrUnsavedRecording = false
    var source: ScreenRecordingSource?
    var events: [String] = []
    var stopCalls = 0
    func present(source: ScreenRecordingSource?) { self.source = source; events.append("present") }
    func stop() { stopCalls += 1; events.append("stop") }
}
