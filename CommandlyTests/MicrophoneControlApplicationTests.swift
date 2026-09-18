import CommandKit
import Infrastructure
import Testing
@testable import Commandly

struct MicrophoneControlApplicationTests {
    @Test @MainActor
    func registeredApplicationLoadsCurrentStateAndTogglesDefaultInputMute() async throws {
        let service = FakeMicrophoneControlService(
            state: MicrophoneControlState(
                deviceName: "Studio Microphone",
                isMuted: false,
                canChangeMute: true
            )
        )
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            microphoneControlService: service
        )
        let definition = try #require(registry.definition(for: MicrophoneControlApplication.id))
        #expect(definition.commandManifest?.title == "Microphone Control")
        #expect(definition.parentID == BuiltInLauncherApplicationGroup.catalogID)

        let application = try #require(registry.application(for: MicrophoneControlApplication.id))
        let launch = application.launch(in: makeContext())
        guard case .present(let session) = launch else {
            Issue.record("Expected Microphone Control to present a session")
            return
        }
        let model = try #require(session.model(as: MicrophoneControlViewModel.self))

        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()

        #expect(model.state?.deviceName == "Studio Microphone")
        #expect(model.isMuted == false)
        #expect(model.primaryActionTitle == "Turn Microphone Off")
        #expect(model.footerActions.first?.id == MicrophoneControlActionID.toggle)

        model.perform(MicrophoneControlActionID.toggle)
        await model.waitForOperationForTesting()

        #expect(await service.recordedMuteValues() == [true])
        #expect(model.isMuted == true)
        #expect(model.primaryActionTitle == "Turn Microphone On")
        #expect(model.statusMessage == "Microphone turned off for the current input device.")
        session.stop()
    }

    @Test @MainActor
    func unsupportedDeviceRemainsVisibleButCannotBeChanged() async {
        let service = FakeMicrophoneControlService(
            state: MicrophoneControlState(
                deviceName: "Virtual Conference Input",
                isMuted: nil,
                canChangeMute: false
            )
        )
        let model = MicrophoneControlViewModel(service: service, onGoBack: {})

        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()
        model.toggleMute()
        await model.waitForOperationForTesting()

        #expect(model.state?.deviceName == "Virtual Conference Input")
        #expect(model.isMuted == nil)
        #expect(model.canChangeMute == false)
        #expect(model.footerActions.first?.id == MicrophoneControlActionID.refresh)
        #expect(await service.recordedMuteValues().isEmpty)
    }

    @Test @MainActor
    func readAndWriteFailuresProduceFocusedRecoverableMessages() async {
        let service = FakeMicrophoneControlService(
            state: MicrophoneControlState(
                deviceName: "MacBook Microphone",
                isMuted: false,
                canChangeMute: true
            ),
            stateError: .noDefaultInputDevice
        )
        let model = MicrophoneControlViewModel(service: service, onGoBack: {})

        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()

        #expect(model.state == nil)
        #expect(model.errorMessage == "No default microphone is available.")
        #expect(model.footerActions.first?.id == MicrophoneControlActionID.refresh)

        await service.setStateError(nil)
        await service.setSetError(
            .hardwareFailure(operation: "set-input-mute", status: -1)
        )
        model.refresh(showSuccessMessage: false)
        await model.waitForRefreshForTesting()
        model.toggleMute()
        await model.waitForOperationForTesting()

        #expect(model.isMuted == false)
        #expect(model.errorMessage == "Couldn’t change the microphone status.")
        #expect(model.statusMessage == "Couldn’t change the microphone status.")
    }

    @MainActor
    private func makeContext() -> LauncherApplicationContext {
        LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )
    }
}

private actor FakeMicrophoneControlService: MicrophoneControlling {
    private var currentState: MicrophoneControlState
    private var stateError: MicrophoneControlError?
    private var setError: MicrophoneControlError?
    private var muteValues: [Bool] = []

    init(
        state: MicrophoneControlState,
        stateError: MicrophoneControlError? = nil,
        setError: MicrophoneControlError? = nil
    ) {
        self.currentState = state
        self.stateError = stateError
        self.setError = setError
    }

    func state() async throws -> MicrophoneControlState {
        if let stateError { throw stateError }
        return currentState
    }

    func setMuted(_ isMuted: Bool) async throws -> MicrophoneControlState {
        muteValues.append(isMuted)
        if let setError { throw setError }
        currentState = MicrophoneControlState(
            deviceName: currentState.deviceName,
            isMuted: isMuted,
            canChangeMute: currentState.canChangeMute
        )
        return currentState
    }

    func recordedMuteValues() -> [Bool] {
        muteValues
    }

    func setStateError(_ error: MicrophoneControlError?) {
        stateError = error
    }

    func setSetError(_ error: MicrophoneControlError?) {
        setError = error
    }
}

