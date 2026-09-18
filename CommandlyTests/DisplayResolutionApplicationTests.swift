import CommandKit
import Testing
@testable import Commandly

@MainActor
struct DisplayResolutionApplicationTests {
    @Test func registeredActionOpensAnIndependentChooserAfterDismissingTheLauncher() async {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let window = ResolutionTestWindow()
        let model = DisplayResolutionCoordinator(controller: DisplayResolutionService(driver: driver, clock: clock),
            clock: clock, ticker: ResolutionTestTicker(), environment: ResolutionTestEnvironment(), window: window,
            openSettings: {}, onRequestQuit: {})
        let application = DisplayResolutionApplication(services: .init(coordinator: model))
        var dismissed = false
        let context = LauncherApplicationContext(navigation: .init(dismissLauncher: { dismissed = true },
            openSettings: {}, openAISettings: {}, goBack: {}),
            settings: .init(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        #expect(application.definition.id == DisplayResolutionApplication.id)
        #expect(application.definition.kind == .application)
        #expect(await driver.snapshotCount == 0)
        _ = application.launch(in: context)
        await model.waitForWorkForTesting()
        #expect(dismissed && window.presentations == 1)
        #expect(await driver.changes.isEmpty)
    }
}
