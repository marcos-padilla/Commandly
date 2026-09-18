import CoreGraphics
import Testing
@testable import Commandly

@Suite("Window Switcher input")
@MainActor
struct WindowSwitcherInputTests {
    @Test func optionHoldSessionCyclesAndCommitsWhenOptionIsReleased() {
        var commands: [WindowSwitcherInputCommand] = []
        let monitor = WindowSwitcherEventMonitor(
            configuration: .default,
            onCommand: { commands.append($0) }
        )

        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate, .maskShift],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskAlternate, .maskShift]
        )))
        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskAlternate]
        )))
        #expect(monitor.handleKeyboardEvent(.flagsChanged([])) == false)

        #expect(commands == [
            .begin(source: .optionTab, reverse: true),
            .cycle(reverse: false),
            .commit,
        ])
    }

    @Test func commandHoldSessionRequiresOptInAndCommitsWhenCommandIsReleased() {
        var disabledCommands: [WindowSwitcherInputCommand] = []
        let disabledMonitor = WindowSwitcherEventMonitor(
            configuration: .default,
            onCommand: { disabledCommands.append($0) }
        )
        #expect(disabledMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: false,
            printableText: nil
        )) == false)
        #expect(disabledMonitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskCommand]
        )) == false)
        #expect(disabledCommands.isEmpty)

        var configuration = WindowSwitcherConfiguration.default
        configuration.replacesCommandTab = true
        var commands: [WindowSwitcherInputCommand] = []
        let monitor = WindowSwitcherEventMonitor(
            configuration: configuration,
            onCommand: { commands.append($0) }
        )

        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskCommand]
        )))
        #expect(monitor.handleKeyboardEvent(.flagsChanged([])) == false)

        #expect(commands == [
            .begin(source: .commandTab, reverse: false),
            .commit,
        ])
    }

    @Test func optionToggleSessionCyclesWithPlainTabAndCancelsWithOptionTab() {
        var configuration = WindowSwitcherConfiguration.default
        configuration.shortcutMode = .toggleOverlay
        var commands: [WindowSwitcherInputCommand] = []
        let monitor = WindowSwitcherEventMonitor(
            configuration: configuration,
            onCommand: { commands.append($0) }
        )

        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskAlternate]
        )))
        #expect(monitor.handleKeyboardEvent(.flagsChanged([])) == false)
        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskShift],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskShift]
        )))
        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate],
            isRepeat: false,
            printableText: nil
        )))
        monitor.endSession()
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskAlternate]
        )))

        #expect(commands == [
            .begin(source: .optionTab, reverse: false),
            .cycle(reverse: true),
            .cancel,
        ])
    }

    @Test func commandToggleSessionCyclesWithPlainTabAndCancelsWithCommandTab() {
        var configuration = WindowSwitcherConfiguration.default
        configuration.shortcutMode = .toggleOverlay
        configuration.replacesCommandTab = true
        var commands: [WindowSwitcherInputCommand] = []
        let monitor = WindowSwitcherEventMonitor(
            configuration: configuration,
            onCommand: { commands.append($0) }
        )

        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskCommand]
        )))
        #expect(monitor.handleKeyboardEvent(.flagsChanged([])) == false)
        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(keyCode: 48, flags: [])))
        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: false,
            printableText: nil
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskCommand]
        )))

        #expect(commands == [
            .begin(source: .commandTab, reverse: false),
            .cycle(reverse: false),
            .cancel,
        ])
    }

    @Test func toggleModifierAutorepeatIsConsumedWithoutCancelling() {
        var optionConfiguration = WindowSwitcherConfiguration.default
        optionConfiguration.shortcutMode = .toggleOverlay
        var optionCommands: [WindowSwitcherInputCommand] = []
        let optionMonitor = WindowSwitcherEventMonitor(
            configuration: optionConfiguration,
            onCommand: { optionCommands.append($0) }
        )

        let optionInitial = optionMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate],
            isRepeat: false,
            printableText: nil
        ))
        let optionRepeat = optionMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate],
            isRepeat: true,
            printableText: nil
        ))

        #expect(optionInitial)
        #expect(optionRepeat)
        #expect(optionCommands == [.begin(source: .optionTab, reverse: false)])

        let optionRelease = optionMonitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskAlternate]
        ))
        let optionReinvoke = optionMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskAlternate],
            isRepeat: false,
            printableText: nil
        ))

        #expect(optionRelease)
        #expect(optionReinvoke)
        #expect(optionCommands == [
            .begin(source: .optionTab, reverse: false),
            .cancel,
        ])

        var commandConfiguration = WindowSwitcherConfiguration.default
        commandConfiguration.shortcutMode = .toggleOverlay
        commandConfiguration.replacesCommandTab = true
        var commandCommands: [WindowSwitcherInputCommand] = []
        let commandMonitor = WindowSwitcherEventMonitor(
            configuration: commandConfiguration,
            onCommand: { commandCommands.append($0) }
        )

        let commandInitial = commandMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: false,
            printableText: nil
        ))
        let commandRepeat = commandMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: true,
            printableText: nil
        ))

        #expect(commandInitial)
        #expect(commandRepeat)
        #expect(commandCommands == [.begin(source: .commandTab, reverse: false)])

        let commandRelease = commandMonitor.handleKeyboardEvent(.keyUp(
            keyCode: 48,
            flags: [.maskCommand]
        ))
        let commandReinvoke = commandMonitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [.maskCommand],
            isRepeat: false,
            printableText: nil
        ))

        #expect(commandRelease)
        #expect(commandReinvoke)
        #expect(commandCommands == [
            .begin(source: .commandTab, reverse: false),
            .cancel,
        ])
    }

    @Test func disabledTapRecoveryCancelsSessionAndClearsKeyState() {
        var commands: [WindowSwitcherInputCommand] = []
        let monitor = WindowSwitcherEventMonitor(
            configuration: .default,
            onCommand: { commands.append($0) }
        )
        monitor.beginToggleSession()
        let searchKeyDown = monitor.handleKeyboardEvent(.keyDown(
            keyCode: 16,
            flags: [],
            isRepeat: false,
            printableText: "y"
        ))

        monitor.recoverFromDisabledTap()

        let staleKeyUp = monitor.handleKeyboardEvent(.keyUp(keyCode: 16, flags: []))
        let tabAfterRecovery = monitor.handleKeyboardEvent(.keyDown(
            keyCode: 48,
            flags: [],
            isRepeat: false,
            printableText: nil
        ))
        monitor.recoverFromDisabledTap()

        #expect(searchKeyDown)
        #expect(staleKeyUp == false)
        #expect(tabAfterRecovery == false)
        #expect(commands == [.appendText("y"), .cancel])
    }

    @Test func consumedSearchKeyConsumesReleaseEvenAfterSessionEnds() {
        var commands: [WindowSwitcherInputCommand] = []
        let monitor = WindowSwitcherEventMonitor(
            configuration: .default,
            onCommand: { commands.append($0) }
        )
        monitor.beginToggleSession()

        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 16,
            flags: [],
            isRepeat: false,
            printableText: "y"
        )))
        monitor.endSession()
        #expect(monitor.handleKeyboardEvent(.keyUp(keyCode: 16, flags: [])))
        #expect(commands == [.appendText("y")])
    }

    @Test func activeSessionConsumesUnsupportedKeyAndItsRelease() {
        var configuration = WindowSwitcherConfiguration.default
        configuration.allowsSearch = false
        configuration.allowsVimNavigation = false
        let monitor = WindowSwitcherEventMonitor(configuration: configuration)
        monitor.beginToggleSession()

        #expect(monitor.handleKeyboardEvent(.keyDown(
            keyCode: 4,
            flags: [],
            isRepeat: false,
            printableText: "h"
        )))
        #expect(monitor.handleKeyboardEvent(.keyUp(keyCode: 4, flags: [])))
    }

    @Test func keyRepeatDoesNotChangeTheInitialReleasePolicy() {
        var consumedTracker = WindowSwitcherKeyConsumptionTracker()
        consumedTracker.recordKeyDown(keyCode: 48, isRepeat: false, wasConsumed: true)
        consumedTracker.recordKeyDown(keyCode: 48, isRepeat: true, wasConsumed: false)
        let consumedRelease = consumedTracker.consumeKeyUp(keyCode: 48)
        #expect(consumedRelease)

        var passedTracker = WindowSwitcherKeyConsumptionTracker()
        passedTracker.recordKeyDown(keyCode: 4, isRepeat: false, wasConsumed: false)
        passedTracker.recordKeyDown(keyCode: 4, isRepeat: true, wasConsumed: true)
        let passedRelease = passedTracker.consumeKeyUp(keyCode: 4)
        #expect(passedRelease == false)
    }
}
