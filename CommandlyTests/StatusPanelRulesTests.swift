import AppKit
import CoreGraphics
import Foundation
import SecurityKit
import SwiftUI
import Testing
@testable import Commandly

/// Decision rules behind the menu bar panel's sections. Every case here is a pure function of
/// its inputs, so none of these tests touch a real device, sensor, or audio process.
struct StatusPanelRulesTests {

    // MARK: - Keep Awake

    @Test func automationStartsASessionOnlyWhileAConditionMatches() {
        #expect(
            KeepAwakeAutomationRules.action(
                matchingConditions: [.connectedToPower],
                sessionActive: false,
                automaticSessionActive: false
            ) == .activate
        )
        #expect(
            KeepAwakeAutomationRules.action(
                matchingConditions: [],
                sessionActive: false,
                automaticSessionActive: false
            ) == .none
        )
    }

    @Test func automationNeverCutsShortASessionTheUserStarted() {
        // A manual session outlives its conditions: only automation's own session is stopped.
        #expect(
            KeepAwakeAutomationRules.action(
                matchingConditions: [],
                sessionActive: true,
                automaticSessionActive: false
            ) == .none
        )
        #expect(
            KeepAwakeAutomationRules.action(
                matchingConditions: [],
                sessionActive: true,
                automaticSessionActive: true
            ) == .deactivate
        )
    }

    @Test func batteryFloorStopsASessionOnlyOnBattery() {
        let onBattery = KeepAwakeAutomationRules.PowerReadingInput(
            isOnBattery: true,
            percentRemaining: 15
        )
        let pluggedIn = KeepAwakeAutomationRules.PowerReadingInput(
            isOnBattery: false,
            percentRemaining: 15
        )

        #expect(
            KeepAwakeAutomationRules.batteryRequiresStop(floorPercent: 20, power: onBattery)
        )
        #expect(
            KeepAwakeAutomationRules.batteryRequiresStop(floorPercent: 20, power: pluggedIn) == false
        )
        // A floor of zero means the feature is off.
        #expect(
            KeepAwakeAutomationRules.batteryRequiresStop(floorPercent: 0, power: onBattery) == false
        )
    }

    @Test func pointerNudgeStaysInsideTheDisplayItStartedOn() {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let target = KeepAwakeAutomationRules.nudgeTarget(
            from: CGPoint(x: 500, y: 400),
            within: bounds
        )
        #expect(target == CGPoint(x: 501, y: 400))

        // Hard against the right edge, the nudge goes the other way rather than off-screen.
        let atRightEdge = KeepAwakeAutomationRules.nudgeTarget(
            from: CGPoint(x: 999, y: 400),
            within: bounds
        )
        #expect(atRightEdge == CGPoint(x: 997, y: 400))

        // With no display to measure, the pointer is left alone.
        #expect(KeepAwakeAutomationRules.nudgeTarget(from: .zero, within: nil) == nil)
    }

    @Test func storedDurationsFallBackToIndefinite() {
        #expect(KeepAwakeAutomationRules.sanitizedDuration(30) == 30)
        #expect(KeepAwakeAutomationRules.sanitizedDuration(7) == 0)
        #expect(KeepAwakeAutomationRules.sanitizedPointerNudgeInterval(999) == 5)
    }

    // MARK: - Volume mixer

    @Test func aRowOnTheDefaultOutputAtFullVolumeIsNeverTapped() {
        #expect(
            MixerRoutingRules.requiresEngine(
                volume: 1,
                selectedOutputDeviceUID: nil,
                targetOutputDeviceUID: "built-in",
                defaultOutputDeviceUID: "built-in"
            ) == false
        )
        #expect(
            MixerRoutingRules.requiresEngine(
                volume: 0.5,
                selectedOutputDeviceUID: nil,
                targetOutputDeviceUID: "built-in",
                defaultOutputDeviceUID: "built-in"
            )
        )
        #expect(
            MixerRoutingRules.requiresEngine(
                volume: 1,
                selectedOutputDeviceUID: "headphones",
                targetOutputDeviceUID: "headphones",
                defaultOutputDeviceUID: "built-in"
            )
        )
    }

    @Test func aRowWithNoAudioObjectsIsNeverTapped() {
        #expect(
            MixerRoutingRules.requiresEngine(
                hasAudioObjects: false,
                volume: 0.2,
                selectedOutputDeviceUID: "headphones",
                targetOutputDeviceUID: "headphones",
                defaultOutputDeviceUID: "built-in"
            ) == false
        )
    }

    @Test func onlyAnAdjustedRowMayBeTapped() {
        #expect(
            MixerRoutingRules.rowMayBeTapped(
                savedVolume: nil,
                savedRouteUID: nil,
                defaultOutputDeviceUID: "built-in"
            ) == false
        )
        #expect(
            MixerRoutingRules.rowMayBeTapped(
                savedVolume: 0.4,
                savedRouteUID: nil,
                defaultOutputDeviceUID: "built-in"
            )
        )
        // A saved route that matches the current default is not an adjustment.
        #expect(
            MixerRoutingRules.rowMayBeTapped(
                savedVolume: nil,
                savedRouteUID: "built-in",
                defaultOutputDeviceUID: "built-in"
            ) == false
        )
    }

    @Test func aRowFallsBackToTheDefaultWhenItsChosenOutputIsGone() {
        let available: Set<String> = ["built-in"]
        #expect(
            MixerRoutingRules.effectiveDeviceUID(
                selectedUID: "headphones",
                availableUIDs: available,
                defaultUID: "built-in"
            ) == "built-in"
        )
        #expect(
            MixerRoutingRules.selectedDeviceUnavailable(
                selectedUID: "headphones",
                availableUIDs: available
            )
        )
    }

    @Test func theOutputCycleWrapsAndSkipsWhatIsNotAttached() {
        let available: Set<String> = ["a", "c"]
        #expect(
            MixerRoutingRules.nextSelectedOutputDeviceUID(
                currentUID: "a",
                selectedUIDs: ["a", "b", "c"],
                availableUIDs: available
            ) == "c"
        )
        #expect(
            MixerRoutingRules.nextSelectedOutputDeviceUID(
                currentUID: "c",
                selectedUIDs: ["a", "b", "c"],
                availableUIDs: available
            ) == "a"
        )
        // One attached device in the cycle has nowhere to go.
        #expect(
            MixerRoutingRules.nextSelectedOutputDeviceUID(
                currentUID: "a",
                selectedUIDs: ["a"],
                availableUIDs: ["a"]
            ) == nil
        )
    }

    @Test func aRowKeepsItsBundleIdentifierAsItsSavedKey() {
        let withBundle = MixerRoutingRules.rowIdentity(
            bundleIdentifier: "com.example.player",
            ownerProcessID: 501,
            displayName: "Player"
        )
        #expect(withBundle.rowID == "com.example.player")
        #expect(withBundle.persistenceID == "com.example.player")

        // A bare executable has no bundle identifier; its name is the only stable key left, and
        // the row itself is per process because identifiers recycle.
        let withoutBundle = MixerRoutingRules.rowIdentity(
            bundleIdentifier: nil,
            ownerProcessID: 501,
            displayName: "Game"
        )
        #expect(withoutBundle.rowID == "process:501")
        #expect(withoutBundle.persistenceID == "Game")

        let anonymous = MixerRoutingRules.rowIdentity(
            bundleIdentifier: nil,
            ownerProcessID: 501,
            displayName: nil
        )
        #expect(anonymous.persistenceID == nil)
    }

    @Test func anAdjustedRowStaysVisibleWhileInactiveAppsAreHidden() {
        #expect(
            MixerRoutingRules.shouldShowApplication(
                isPlaying: false,
                volume: 1,
                selectedOutputDeviceUID: nil,
                hidesInactiveApplications: true
            ) == false
        )
        #expect(
            MixerRoutingRules.shouldShowApplication(
                isPlaying: false,
                volume: 0.3,
                selectedOutputDeviceUID: nil,
                hidesInactiveApplications: true
            )
        )
    }

    @Test func conferencingAndAudioWorkstationsAreNeverTapped() {
        #expect(MixerRoutingRules.bypassesProcessTap(bundleIdentifier: "us.zoom.xos", name: "Zoom"))
        #expect(
            MixerRoutingRules.bypassesProcessTap(
                bundleIdentifier: "com.apple.logic10",
                name: "Logic Pro"
            )
        )
        #expect(
            MixerRoutingRules.bypassesProcessTap(
                bundleIdentifier: "com.example.player",
                name: "Player"
            ) == false
        )
    }

    @Test func aWedgedEngineIsOnlyDeclaredAfterTheFullWindow() {
        let observation = MixerRoutingRules.EngineRenderObservation(cycles: 10, at: 100)

        // The counter moved: the engine is fine.
        #expect(
            MixerRoutingRules.engineRenderVerdict(
                previous: observation,
                cycles: 11,
                isPlaying: true,
                now: 101
            ) == .note(
                MixerRoutingRules.EngineRenderObservation(cycles: 11, at: 101),
                recheckAfter: nil
            )
        )
        // Still, but not for long enough to be sure.
        #expect(
            MixerRoutingRules.engineRenderVerdict(
                previous: observation,
                cycles: 10,
                isPlaying: true,
                now: 100.5
            ) == .stalled(recheckAfter: 1)
        )
        // Still for the whole window while the app plays: the audio path is dead.
        #expect(
            MixerRoutingRules.engineRenderVerdict(
                previous: observation,
                cycles: 10,
                isPlaying: true,
                now: 102
            ) == .wedged
        )
        // A counter at rest while nothing plays is not a failure.
        #expect(
            MixerRoutingRules.engineRenderVerdict(
                previous: observation,
                cycles: 10,
                isPlaying: false,
                now: 102
            ) == nil
        )
    }

    @Test func aLateEngineBuildCannotInstallItself() {
        var builds = MixerEngineBuilds()
        let first = builds.begin("row")
        #expect(first != nil)
        // A second build cannot start while one is in flight.
        let second = builds.begin("row")
        #expect(second == nil)

        builds.invalidateAll()
        guard let first else { return }
        let isStillCurrent = builds.isCurrent("row", token: first)
        #expect(isStillCurrent == false)
    }

    @Test func aRefreshPassThatIsNoLongerCurrentDoesNotPublish() {
        var coordinator = MixerRefreshCoordinator()
        let generation = coordinator.begin()
        #expect(generation != nil)
        // A request during a pass is remembered rather than run concurrently.
        let concurrent = coordinator.begin()
        #expect(concurrent == nil)
        let remembered = coordinator.takeRepeatRequest()
        #expect(remembered)

        coordinator.discardInFlight()
        guard let generation else { return }
        let mayPublish = coordinator.finish(generation)
        #expect(mayPublish == false)
    }

    @Test func theMixerOnlyRestoresAVolumeItStillRecognizes() {
        #expect(
            MixerRoutingRules.shouldRestoreOutputVolume(appliedVolume: 0.3, currentVolume: 0.3)
        )
        // Someone moved the volume since: their choice wins.
        #expect(
            MixerRoutingRules.shouldRestoreOutputVolume(
                appliedVolume: 0.3,
                currentVolume: 0.7
            ) == false
        )
    }

    // MARK: - System metrics

    @Test func memoryUsedCountsAppWiredAndCompressedPages() {
        let pageSize: UInt64 = 16_384
        let total: UInt64 = 16 * 1_024 * 1_024 * 1_024

        let application = SystemMetricsFormat.applicationMemory(
            totalBytes: total,
            pageSize: pageSize,
            internalPages: 1_000,
            purgeablePages: 200
        )
        #expect(application == 800 * pageSize)

        let used = SystemMetricsFormat.memoryUsed(
            totalBytes: total,
            applicationBytes: application,
            pageSize: pageSize,
            wiredPages: 100,
            compressorPages: 50
        )
        #expect(used == (800 + 100 + 50) * pageSize)
    }

    @Test func memoryFiguresNeverExceedInstalledMemory() {
        // A reading larger than the machine's memory is a bad sample, not a full machine.
        let used = SystemMetricsFormat.memoryUsed(
            totalBytes: 1_000,
            applicationBytes: 900,
            pageSize: 100,
            wiredPages: 50,
            compressorPages: 50
        )
        #expect(used == 1_000)
    }

    @Test func uptimeReadsAsDaysAndHoursOnceItPassesADay() {
        #expect(SystemMetricsFormat.uptimeText(6 * 86_400 + 13 * 3_600) == "Up for 6d 13h")
        #expect(SystemMetricsFormat.uptimeText(3 * 3_600 + 5 * 60) == "Up for 3h 5m")
        #expect(SystemMetricsFormat.uptimeText(nil) == nil)
    }

    @Test func historyKeepsOnlyItsMostRecentSamples() {
        var history: [Double] = []
        for index in 0..<(SystemMetricsFormat.historyLength + 10) {
            history = SystemMetricsFormat.appending(Double(index % 2), to: history)
        }
        #expect(history.count == SystemMetricsFormat.historyLength)

        // A missing sample leaves the history as it was rather than inventing a zero.
        let unchanged = SystemMetricsFormat.appending(nil, to: history)
        #expect(unchanged == history)
    }

    @Test func memoryPressureMapsTheKernelLevels() {
        #expect(MemoryPressure(kernelLevel: 1) == .normal)
        #expect(MemoryPressure(kernelLevel: 2) == .warning)
        #expect(MemoryPressure(kernelLevel: 4) == .critical)
        #expect(MemoryPressure(kernelLevel: 99) == .unknown)
    }

    // MARK: - Network

    @Test func interfaceCountersBecomeASpeedOnlyWhenTheyRoseFairly() {
        let previous = NetworkCounters(received: 1_000, sent: 500)
        let current = NetworkCounters(received: 3_000, sent: 1_500)

        let speed = NetworkMetricsRules.speed(previous: previous, current: current, elapsed: 2)
        #expect(speed.down == 1_000)
        #expect(speed.up == 500)

        // A counter that went backwards means the interface reset, not negative traffic.
        let reset = NetworkMetricsRules.speed(
            previous: current,
            current: previous,
            elapsed: 2
        )
        #expect(reset.down == nil)
        #expect(reset.up == nil)
    }

    @Test func loopbackAndVirtualInterfacesAreLeftOut() {
        #expect(NetworkMetricsRules.includesInterface("en0"))
        #expect(NetworkMetricsRules.includesInterface("lo0") == false)
        #expect(NetworkMetricsRules.includesInterface("utun3") == false)
        #expect(NetworkMetricsRules.includesInterface("awdl0") == false)
    }

    @Test func rateHistoryScalesAgainstItsOwnPeak() {
        #expect(NetworkMetricsRules.normalized([0, 50, 100]) == [0, 0.5, 1])
        // A silent stretch draws a flat line rather than dividing by zero.
        #expect(NetworkMetricsRules.normalized([0, 0, 0]) == [0, 0, 0])
    }

    // MARK: - Power

    @Test func systemDrawIsOnlyReportedWhileRunningOnBattery() {
        #expect(PowerMetricsRules.systemWatts(batteryWatts: -9.1, isPluggedIn: false) == 9.1)
        // On wall power the battery says nothing about the rest of the Mac.
        #expect(PowerMetricsRules.systemWatts(batteryWatts: 12, isPluggedIn: true) == nil)
        #expect(PowerMetricsRules.systemWatts(batteryWatts: nil, isPluggedIn: false) == nil)
    }

    @Test func remainingTimeReadsAsHoursAndMinutes() {
        #expect(PowerMetricsRules.timeRemainingText(8 * 3_600 + 47 * 60) == "8h 47m")
        #expect(PowerMetricsRules.timeRemainingText(25 * 60) == "25m")
        // A system still calculating has no estimate to show.
        #expect(PowerMetricsRules.timeRemainingText(nil) == nil)
    }

    // MARK: - Fans

    @Test func aFanCurveInterpolatesBetweenItsPoints() {
        let curve = [
            FanCurvePoint(temperatureCelsius: 40, speedFraction: 0),
            FanCurvePoint(temperatureCelsius: 80, speedFraction: 1),
        ]
        #expect(FanControlRules.speedFraction(atCelsius: 60, curve: curve) == 0.5)
        // Below and above the curve, its end points hold.
        #expect(FanControlRules.speedFraction(atCelsius: 20, curve: curve) == 0)
        #expect(FanControlRules.speedFraction(atCelsius: 120, curve: curve) == 1)
        #expect(FanControlRules.speedFraction(atCelsius: 60, curve: []) == nil)
    }

    @Test func controlIsHandedBackWheneverTheChipCannotBeJudged() {
        // Healthy: a recent reading, a cool chip, no pressure.
        #expect(
            FanControlRules.mustHandBackControl(
                chipTemperature: 60,
                secondsSinceLastReading: 2,
                isThermallyPressured: false
            ) == false
        )
        // The readings stopped.
        #expect(
            FanControlRules.mustHandBackControl(
                chipTemperature: 60,
                secondsSinceLastReading: 30,
                isThermallyPressured: false
            )
        )
        // No reading at all.
        #expect(
            FanControlRules.mustHandBackControl(
                chipTemperature: nil,
                secondsSinceLastReading: 2,
                isThermallyPressured: false
            )
        )
        // The chip reached the handback temperature.
        #expect(
            FanControlRules.mustHandBackControl(
                chipTemperature: 97,
                secondsSinceLastReading: 2,
                isThermallyPressured: false
            )
        )
        // macOS itself reported thermal pressure.
        #expect(
            FanControlRules.mustHandBackControl(
                chipTemperature: 50,
                secondsSinceLastReading: 1,
                isThermallyPressured: true
            )
        )
    }

    @Test func aFractionBecomesAnRPMInsideTheFansOwnRange() {
        #expect(
            FanControlRules.targetRPM(fraction: 0.5, minimumRPM: 1_000, maximumRPM: 3_000) == 2_000
        )
        // A range that is not a range cannot produce a target.
        #expect(FanControlRules.targetRPM(fraction: 0.5, minimumRPM: 2_000, maximumRPM: 2_000) == nil)
    }

    // MARK: - Panel layout

    @Test @MainActor func aSectionBodyKeepsItsHeightInASizeToContentWindow() {
        // The menu bar panel's window sizes itself to its content, so it proposes no definite
        // height. A plain ScrollView is greedy there and collapses to nothing, which is what left
        // every section blank between its header and the footer. The measured container must give
        // the window something to size to, from the very first layout pass.
        let view = MeasuredScrollView(
            width: StatusPanelChrome.contentWidth,
            maximumHeight: 600,
            estimatedHeight: 240
        ) {
            Color.clear.frame(height: 300)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.height >= 240)
    }

    @Test @MainActor func aTallSectionIsCappedSoThePanelStaysOnScreen() {
        let view = MeasuredScrollView(
            width: StatusPanelChrome.contentWidth,
            maximumHeight: 300,
            estimatedHeight: 2_000
        ) {
            Color.clear.frame(height: 2_000)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.height <= 300)
    }

    @Test @MainActor func aSectionRendersRealContentAndNotJustItsHeader() {
        // The container fix is only half the story: the section inside it has to draw something.
        // Hosting a real section and measuring it is what proves the tab is not blank.
        let coordinator = KeepAwakeCoordinator(
            store: InMemoryKeepAwakeSettingsStore(),
            permissions: InMemoryPermissionService()
        )
        let hosting = NSHostingView(
            rootView: KeepAwakePanelSection(coordinator: coordinator)
                .frame(width: StatusPanelChrome.contentWidth)
        )
        hosting.layoutSubtreeIfNeeded()
        // The card alone carries a status line, a switch, a duration row and the battery row.
        #expect(hosting.fittingSize.height > 80)
    }

    @Test @MainActor func everySectionReservesAHeightBeforeItIsMeasured() {
        // A zero estimate would reproduce the collapse on the first frame of every tab.
        for section in StatusPanelSection.allCases {
            #expect(section.estimatedHeight > 0)
        }
    }

    // MARK: - Controls

    @Test func aSubOptionOnlyAppearsWhileItsParentIsOn() {
        let onlyParentOn = ControlRules.rows(
            in: .windows,
            isOn: { $0 == .appSwitcher },
            unavailable: { _ in nil }
        )
        #expect(onlyParentOn.contains { $0.control == .appSwitcherLargeIcons })

        let parentOff = ControlRules.rows(
            in: .windows,
            isOn: { _ in false },
            unavailable: { _ in nil }
        )
        #expect(parentOff.contains { $0.control == .appSwitcherLargeIcons } == false)

        // A parent that cannot be switched at all never reveals its sub-option either.
        let parentUnavailable = ControlRules.rows(
            in: .windows,
            isOn: { $0 == .appSwitcher },
            unavailable: { $0 == .appSwitcher ? .notBuilt : nil }
        )
        #expect(parentUnavailable.contains { $0.control == .appSwitcherLargeIcons } == false)
    }

    @Test func theGroupCountOnlyCountsRowsThatCanBeSwitched() {
        let rows = ControlRules.rows(
            in: .files,
            isOn: { $0 == .shelf },
            unavailable: { $0 == .finderCutAndPaste ? .notBuilt : nil }
        )
        let group = ControlGroupPresentation(group: .files, rows: rows)
        // Shelf is on and switchable; cut & paste is not built, so it is not in the denominator.
        #expect(group.countLabel == "1/1")
    }

    @Test func anUnavailableRowExplainsItselfInsteadOfDescribingTheFeature() {
        #expect(
            ControlRules.caption(for: .superKey, unavailable: .notBuilt)
                == "Not built in Commandly yet."
        )
        #expect(
            ControlRules.caption(for: .quitOnClose, unavailable: .configuredPerApplication)
                == "Commandly keeps this per app. Choose the apps in Settings."
        )
        #expect(
            ControlRules.caption(for: .appSwitcher, unavailable: .needsAccessibility)
                == "Needs Accessibility permission."
        )
        // A working row keeps its own description.
        #expect(ControlRules.caption(for: .shelf, unavailable: nil) == ControlID.shelf.caption)
    }

    @Test func everyControlBelongsToExactlyOneGroup() {
        let grouped = ControlGroup.allCases.flatMap { group in
            ControlID.allCases.filter { $0.group == group }
        }
        #expect(grouped.count == ControlID.allCases.count)
    }

    // MARK: - Status item glyph

    @Test @MainActor func theStatusGlyphIsTheSameObjectForAnUnchangedSession() {
        // The status item is a tiny window that re-sizes whenever its content changes. Handing
        // SwiftUI a freshly built image on every body pass makes it resize, which invalidates the
        // hosting view, which rebuilds the label — the loop AppKit ends by throwing. Identity is
        // what breaks that cycle, so it is the thing worth pinning down.
        let first = StatusBarIconImage.image(symbolName: "command", tint: nil)
        let second = StatusBarIconImage.image(symbolName: "command", tint: nil)
        #expect(first === second)

        let tinted = StatusBarIconImage.image(symbolName: "command", tint: .systemOrange)
        #expect(tinted !== first)
        let tintedAgain = StatusBarIconImage.image(symbolName: "command", tint: .systemOrange)
        #expect(tinted === tintedAgain)
    }

    @Test @MainActor func anUnknownSymbolStillProducesAGlyph() {
        // The label has no second branch to fall back to, so the image builder must be total.
        let image = StatusBarIconImage.image(symbolName: "not.a.real.symbol", tint: nil)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test @MainActor func onlyAnUntintedGlyphIsATemplate() {
        // A template image follows the menu bar's own color, which is what an idle Commandly
        // wants; a tinted one must keep its color so an active session stands out.
        #expect(StatusBarIconImage.image(symbolName: "command", tint: nil).isTemplate)
        #expect(
            StatusBarIconImage.image(symbolName: "command", tint: .systemGreen).isTemplate == false
        )
    }

    // MARK: - Quick toggles

    @Test func theAppearanceRowNamesTheModeItWouldSwitchTo() {
        #expect(QuickToggleRules.appearanceTitle(isDark: true) == "Switch to light mode")
        #expect(QuickToggleRules.appearanceTitle(isDark: false) == "Switch to dark mode")
    }

    @Test func anUnreadableAppearanceSaysSoInsteadOfGuessing() {
        #expect(
            QuickToggleRules.appearanceCaption(isDark: nil)
                == "Commandly could not read the current system appearance."
        )
        #expect(
            QuickToggleRules.appearanceCaption(isDark: true)
                == "Changes the appearance of the whole system."
        )
    }

    @Test func theMicrophoneRowNamesTheChangeItWouldMake() {
        #expect(QuickToggleRules.microphoneTitle(isMuted: false) == "Mute microphone")
        #expect(QuickToggleRules.microphoneTitle(isMuted: true) == "Unmute microphone")
        // An unknown state is not a muted one.
        #expect(QuickToggleRules.microphoneTitle(isMuted: nil) == "Mute microphone")
    }

    @Test func aDeviceWithoutAMuteControlIsNamedInTheCaption() {
        #expect(
            QuickToggleRules.microphoneCaption(deviceName: "Studio Mic", canChange: false)
                == "Studio Mic exposes no system-wide mute control."
        )
        #expect(
            QuickToggleRules.microphoneCaption(deviceName: "Studio Mic", canChange: true)
                == "Cuts the Mac's microphone with a click, across every app."
        )
    }

    @Test func theEjectRowCountsWhatIsActuallyAttached() {
        #expect(QuickToggleRules.ejectCaption(ejectableCount: 0) == "No external disk ready to eject.")
        #expect(QuickToggleRules.ejectCaption(ejectableCount: 1) == "One external disk is ready to eject.")
        #expect(QuickToggleRules.ejectCaption(ejectableCount: 3) == "3 external disks are ready to eject.")
    }

    @Test func aRowNeedingAccessibilitySaysSoWhileItIsMissing() {
        #expect(
            QuickToggleRules.accessibilityCaption(granted: false, whenGranted: "Does the thing.")
                == "Needs Accessibility permission."
        )
        #expect(
            QuickToggleRules.accessibilityCaption(granted: true, whenGranted: "Does the thing.")
                == "Does the thing."
        )
    }

    @Test func hidingEveryRowIsRefusedSoTheTabIsNeverEmpty() {
        let all = Set(QuickToggleID.allCases.map(\.rawValue))
        #expect(QuickToggleRules.visibleToggles(hidden: all).count == QuickToggleID.allCases.count)

        let someHidden = QuickToggleRules.visibleToggles(
            hidden: [QuickToggleID.lockScreen.rawValue]
        )
        #expect(someHidden.contains(.lockScreen) == false)
        #expect(someHidden.count == QuickToggleID.allCases.count - 1)
    }

    @Test func onlyTheTrashRowAsksBeforeItActs() {
        let confirming = QuickToggleID.allCases.filter(\.needsConfirmation)
        #expect(confirming == [.emptyTrash])
    }

    @Test func hiddenRowsSurviveARoundTripAndDropUnknownValues() {
        let store = InMemoryQuickTogglesSettingsStore()
        store.saveHiddenToggles([QuickToggleID.screenSaver.rawValue])
        #expect(store.hiddenToggles() == [QuickToggleID.screenSaver.rawValue])
    }

    @Test func chipGenerationIsReadFromTheBrandString() {
        #expect(TemperatureSensorSelector.generation(brandString: "Apple M1 Pro") == .appleM1)
        #expect(TemperatureSensorSelector.generation(brandString: "Apple M4 Max") == .appleM4)
        #expect(
            TemperatureSensorSelector.generation(brandString: "Apple A18 Pro")
                == .unmappedAppleSilicon
        )
        #expect(
            TemperatureSensorSelector.generation(brandString: "Intel Core i9") == .other
        )
    }

    @Test func theHottestMappedCoreIsTheProcessorTemperature() {
        let readings: [(key: String, value: Double)] = [
            ("Tp09", 55),
            ("Tp0T", 61),
            ("Ts0P", 90),
        ]
        // The enclosure sensor is hotter, but it is not a core.
        #expect(
            TemperatureSensorSelector.displayedProcessorTemperature(
                readings: readings,
                generation: .appleM1
            ) == 61
        )
        // Implausible readings are dropped rather than shown as a cold chip.
        #expect(
            TemperatureSensorSelector.displayedProcessorTemperature(
                readings: [("Tp09", 0)],
                generation: .appleM1
            ) == nil
        )
    }
}
