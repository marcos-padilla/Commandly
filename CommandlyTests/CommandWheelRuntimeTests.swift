import AppKit
import CommandKit
import CoreGraphics
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct CommandWheelRuntimeTests {
    @Test @MainActor
    func holdReleaseTakesFinalSampleAndDispatchesSharedExecutionExactlyOnce() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .holdAndRelease)
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        await waitForPresentation(fixture.coordinator)

        fixture.pointer.location = CGPoint(x: 500, y: 600)
        fixture.coordinator.shortcutReleased(sessionToken: token)
        fixture.coordinator.shortcutReleased(sessionToken: token)
        await waitForExecutionCount(1, executor: fixture.executor)

        let calls = await fixture.executor.calls
        #expect(calls.count == 1)
        #expect(calls.first?.reference.commandID == fixture.commandID)
        #expect(calls.first?.context.screenIdentifier == "display-main")
        #expect(
            calls.first?.context.frontmostApplicationBundleIdentifier
                == "com.example.frontmost"
        )
        guard case .commandWheel(
            profileID: fixture.profile.id,
            pageID: fixture.profile.rootPageID,
            segmentID: fixture.segmentID
        )? = calls.first?.context.source else {
            Issue.record("Expected privacy-safe Command Wheel invocation context")
            return
        }
        #expect(fixture.window.dismissCount == 1)
        #expect(fixture.window.pressedSlotAtDismiss == 0)
        #expect(fixture.input.isActive == false)
        #expect(fixture.coordinator.presentationState == .idle)
    }

    @Test @MainActor
    func releaseDuringPreparationRetainsFinalFastFlickAndExecutesOnce() async throws {
        let preparationGate = RuntimeAsyncGate()
        let fixture = makeCoordinatorFixture(
            activationBehavior: .holdAndRelease,
            preparationGate: preparationGate
        )
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))

        fixture.pointer.location = CGPoint(x: 500, y: 600)
        fixture.coordinator.shortcutReleased(sessionToken: token)
        fixture.coordinator.shortcutReleased(sessionToken: token)
        #expect(fixture.window.presentCount == 0)
        guard case .preparing = fixture.coordinator.presentationState else {
            Issue.record("The released gesture must remain owned while content preparation finishes")
            return
        }

        await preparationGate.open()
        await waitForExecutionCount(1, executor: fixture.executor)

        #expect(await fixture.executor.calls.count == 1)
        #expect(fixture.window.presentCount == 0)
        #expect(fixture.coordinator.presentationState == .idle)
    }

    @Test @MainActor
    func pendingReleaseDoesNotExecuteAfterFrontmostContextChangesDuringPreparation() async throws {
        let preparationGate = RuntimeAsyncGate()
        let fixture = makeCoordinatorFixture(
            activationBehavior: .holdAndRelease,
            preparationGate: preparationGate
        )
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        #expect(fixture.window.isObservingLifecycle)

        fixture.pointer.location = CGPoint(x: 500, y: 600)
        fixture.coordinator.shortcutReleased(sessionToken: token)
        fixture.contextProvider.context = FrontmostApplicationContext(
            processIdentifier: 88,
            bundleIdentifier: "com.example.replacement",
            localizedName: "Replacement"
        )

        await preparationGate.open()
        await waitForSessionEnd(fixture.coordinator)

        #expect(await fixture.executor.calls.isEmpty)
        #expect(fixture.window.presentCount == 0)
        #expect(fixture.window.isObservingLifecycle == false)
        #expect(fixture.coordinator.presentationState == .idle)
    }

    @Test @MainActor
    func pendingReleaseDoesNotExecuteAfterDisplayTopologyChangesDuringPreparation() async throws {
        let preparationGate = RuntimeAsyncGate()
        let fixture = makeCoordinatorFixture(
            activationBehavior: .holdAndRelease,
            preparationGate: preparationGate
        )
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        #expect(fixture.window.isObservingLifecycle)

        fixture.pointer.location = CGPoint(x: 500, y: 600)
        fixture.coordinator.shortcutReleased(sessionToken: token)
        fixture.display.isConnected = false

        await preparationGate.open()
        await waitForSessionEnd(fixture.coordinator)

        #expect(await fixture.executor.calls.isEmpty)
        #expect(fixture.window.presentCount == 0)
        #expect(fixture.window.isObservingLifecycle == false)
        #expect(fixture.coordinator.presentationState == .idle)
    }

    @Test @MainActor
    func activeSpaceChangeCancelsPendingReleaseWhilePreparationIsInFlight() async throws {
        let preparationGate = RuntimeAsyncGate()
        let fixture = makeCoordinatorFixture(
            activationBehavior: .holdAndRelease,
            preparationGate: preparationGate
        )
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        fixture.coordinator.shortcutReleased(sessionToken: token)
        #expect(fixture.window.isObservingLifecycle)

        fixture.window.fireActiveSpaceChanged()
        #expect(fixture.coordinator.activeSessionToken == nil)
        #expect(fixture.window.isObservingLifecycle == false)

        await preparationGate.open()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(await fixture.executor.calls.isEmpty)
        #expect(fixture.window.presentCount == 0)
        #expect(fixture.coordinator.presentationState == .idle)
    }

    @Test @MainActor
    func toggleClickInTransparentPanelMarginCancelsAndPassesThrough() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .toggle)
        _ = fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id)
        await waitForPresentation(fixture.coordinator)

        let disposition = fixture.monitors.sendLocal(CommandWheelClickEvent(
            screenLocation: CGPoint(x: 500, y: 700),
            button: .left,
            source: .local
        ))

        #expect(disposition == .passThrough)
        #expect(fixture.coordinator.activeSessionToken == nil)
        #expect(await fixture.executor.calls.isEmpty)
    }

    @Test @MainActor
    func frontmostApplicationChangeCancelsButIntentionalToggleActivationDoesNot() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .toggle)
        _ = fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id)
        await waitForPresentation(fixture.coordinator)

        fixture.window.fireFrontmostApplicationChanged(
            ProcessInfo.processInfo.processIdentifier
        )
        #expect(fixture.coordinator.activeSessionToken != nil)

        fixture.window.fireFrontmostApplicationChanged(9_999)
        #expect(fixture.coordinator.activeSessionToken == nil)
        #expect(fixture.coordinator.presentationState == .idle)
        #expect(await fixture.executor.calls.isEmpty)
    }

    @Test @MainActor
    func oldReleaseCannotMutateANewerSession() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .holdAndRelease)
        let oldToken = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        fixture.coordinator.shortcutCancelled(sessionToken: oldToken)

        let currentToken = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        await waitForPresentation(fixture.coordinator)
        fixture.coordinator.shortcutReleased(sessionToken: oldToken)

        #expect(fixture.coordinator.activeSessionToken == currentToken)
        guard case .tracking = fixture.coordinator.presentationState else {
            Issue.record("A stale release must leave the current tracking session intact")
            return
        }
        #expect(await fixture.executor.calls.isEmpty)
        fixture.coordinator.shortcutCancelled(sessionToken: currentToken)
    }

    @Test @MainActor
    func toggleSecondPressAndAnyDisplayGeometryChangeDismissWithoutExecution() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .toggle)
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        await waitForPresentation(fixture.coordinator)
        #expect(fixture.input.hasClickMonitors)

        fixture.window.fireDisplayConfigurationChanged()
        #expect(fixture.coordinator.activeSessionToken == nil)
        #expect(fixture.coordinator.presentationState == .idle)
        #expect(await fixture.executor.calls.isEmpty)

        _ = fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id)
        await waitForPresentation(fixture.coordinator)
        #expect(fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id) == nil)
        #expect(fixture.coordinator.presentationState == .idle)
        fixture.coordinator.shortcutCancelled(sessionToken: token)
    }

    @Test @MainActor
    func settingsDisableAndApplicationTerminationCancelOwnedResources() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .toggle)
        _ = fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id)
        await waitForPresentation(fixture.coordinator)

        var disabledConfiguration = CommandWheelConfiguration(
            isEnabled: false,
            contextAwareProfileSelectionEnabled: false,
            defaultProfileID: fixture.profile.id,
            profiles: [fixture.profile]
        )
        fixture.coordinator.updateConfiguration(disabledConfiguration)

        #expect(fixture.coordinator.activeSessionToken == nil)
        #expect(fixture.coordinator.presentationState == .idle)
        #expect(fixture.input.isActive == false)
        #expect(fixture.window.isPresented == false)
        #expect(await fixture.executor.calls.isEmpty)

        disabledConfiguration.isEnabled = true
        fixture.coordinator.updateConfiguration(disabledConfiguration)
        _ = fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id)
        await waitForPresentation(fixture.coordinator)
        fixture.window.fireApplicationWillTerminate()

        #expect(fixture.coordinator.activeSessionToken == nil)
        #expect(fixture.coordinator.presentationState == .idle)
        #expect(fixture.input.isActive == false)
        #expect(fixture.window.isPresented == false)
        #expect(await fixture.executor.calls.isEmpty)
    }

    @Test @MainActor
    func toggleKeyboardSkipsEmptySlotsAndReturnExecutesSelection() async throws {
        let fixture = makeCoordinatorFixture(activationBehavior: .toggle)
        _ = fixture.coordinator.shortcutPressed(explicitProfileID: fixture.profile.id)
        await waitForPresentation(fixture.coordinator)

        #expect(fixture.coordinator.handleKeyboardCommand(.next))
        #expect(fixture.coordinator.presentationModel?.selectedSlotIndex == 0)
        #expect(fixture.coordinator.handleKeyboardCommand(.activate))
        await waitForExecutionCount(1, executor: fixture.executor)

        #expect(await fixture.executor.calls.count == 1)
        #expect(fixture.coordinator.presentationState == .idle)
    }

    @Test @MainActor
    func directionalSubmenuTraversalAndCenterReturnUseFrozenPages() async throws {
        let fixture = makeCoordinatorFixture(
            activationBehavior: .holdAndRelease,
            includesSubmenu: true
        )
        let token = try #require(fixture.coordinator.shortcutPressed(
            explicitProfileID: fixture.profile.id
        ))
        await waitForPresentation(fixture.coordinator)

        fixture.pointer.location = CGPoint(x: 500, y: 640)
        fixture.pointerScheduler.tasks.last?.fire()
        #expect(fixture.coordinator.presentationModel?.pageID == fixture.childPageID)
        #expect(fixture.coordinator.presentationModel?.centerAction == .back)

        // One outward child-page sample arms the intentional center-return gesture.
        fixture.pointerScheduler.tasks.last?.fire()
        fixture.pointer.location = CGPoint(x: 500, y: 500)
        fixture.pointerScheduler.tasks.last?.fire()
        #expect(fixture.coordinator.presentationModel?.pageID == fixture.profile.rootPageID)
        #expect(fixture.coordinator.presentationModel?.centerAction == .cancel)
        #expect(await fixture.executor.calls.isEmpty)
        fixture.coordinator.shortcutCancelled(sessionToken: token)
    }

    @Test @MainActor
    func inputLifecycleOwnsModeSpecificMonitorsAndFinalPointerSample() throws {
        let pointer = RuntimePointerProvider(location: CGPoint(x: 10, y: 10))
        let scheduler = RuntimeTimerScheduler()
        let monitors = RuntimeEventMonitorManager()
        let lifecycle = CommandWheelInputLifecycle(
            pointerSampler: CommandWheelPointerSampler(
                pointerProvider: pointer,
                timerScheduler: scheduler
            ),
            eventMonitors: monitors
        )
        var samples = [CommandWheelPointerSample]()
        var insideClicks = [CGPoint]()
        var outsideClickCount = 0

        lifecycle.start(
            mode: .holdAndRelease,
            panelFrame: { CGRect(x: 0, y: 0, width: 100, height: 100) },
            interactiveRegionContains: { CGRect(x: 0, y: 0, width: 100, height: 100).contains($0) },
            onPointerSample: { samples.append($0) },
            onInsideClick: { insideClicks.append($0) },
            onOutsideClick: { outsideClickCount += 1 }
        )
        #expect(lifecycle.isSampling)
        #expect(monitors.installCount == 0)
        lifecycle.stop()

        lifecycle.start(
            mode: .toggle,
            panelFrame: { CGRect(x: 0, y: 0, width: 100, height: 100) },
            interactiveRegionContains: { point in
                hypot(point.x - 50, point.y - 50) <= 40
            },
            onPointerSample: { samples.append($0) },
            onInsideClick: { insideClicks.append($0) },
            onOutsideClick: { outsideClickCount += 1 }
        )
        #expect(monitors.installCount == 1)
        #expect(
            monitors.sendLocal(
                CommandWheelClickEvent(
                    screenLocation: CGPoint(x: 25, y: 25),
                    button: .left,
                    source: .local
                )
            ) == .consume
        )
        #expect(insideClicks == [CGPoint(x: 25, y: 25)])
        #expect(
            monitors.sendLocal(
                CommandWheelClickEvent(
                    screenLocation: CGPoint(x: 95, y: 50),
                    button: .left,
                    source: .local
                )
            ) == .passThrough
        )
        #expect(outsideClickCount == 1)
        #expect(
            monitors.sendLocal(
                CommandWheelClickEvent(
                    screenLocation: CGPoint(x: 125, y: 25),
                    button: .left,
                    source: .local
                )
            ) == .passThrough
        )
        #expect(outsideClickCount == 2)

        pointer.location = CGPoint(x: 80, y: 90)
        lifecycle.sampleFinalAndStop()
        #expect(samples.last == CommandWheelPointerSample(
            location: CGPoint(x: 80, y: 90),
            isFinal: true
        ))
        #expect(lifecycle.isActive == false)
        #expect(monitors.removeCount >= 2)
        #expect(scheduler.tasks.allSatisfy { $0.isCancelled })
    }

    #if DEBUG
    @Test @MainActor
    func nativeGlobalMonitorRejectsQueuedCallbackFromPreviousInstallation() {
        let manager = NSEventCommandWheelEventMonitorManager()
        var firstDeliveryCount = 0
        var secondDeliveryCount = 0
        manager.installHandlersForTesting { _ in
            firstDeliveryCount += 1
        }
        let staleGeneration = manager.callbackGenerationForTesting

        manager.installHandlersForTesting { _ in
            secondDeliveryCount += 1
        }
        let currentGeneration = manager.callbackGenerationForTesting
        let event = CommandWheelClickEvent(
            screenLocation: CGPoint(x: 100, y: 200),
            button: .left,
            source: .global
        )

        manager.deliverGlobalForTesting(event, generation: staleGeneration)
        #expect(firstDeliveryCount == 0)
        #expect(secondDeliveryCount == 0)

        manager.deliverGlobalForTesting(event, generation: currentGeneration)
        #expect(secondDeliveryCount == 1)

        manager.removeAll()
        manager.deliverGlobalForTesting(event, generation: currentGeneration)
        #expect(secondDeliveryCount == 1)
    }
    #endif

    @Test @MainActor
    func nativePanelUsesTransientFullScreenOverlayFlagsAndExplicitObserverLifecycle() async throws {
        _ = NSApplication.shared
        let notifications = NotificationCenter()
        let workspaceNotifications = NotificationCenter()
        let focus = RuntimeFocusRestorer()
        let activator = RuntimeApplicationActivator()
        let controller = CommandWheelWindowController(
            notificationCenter: notifications,
            workspaceNotificationCenter: workspaceNotifications,
            focusRestorer: focus,
            applicationActivator: activator
        )
        var displayChangeCount = 0
        controller.setLifecycleHandlers(
            displayConfigurationChanged: { displayChangeCount += 1 },
            activeSpaceChanged: {},
            frontmostApplicationChanged: { _ in },
            applicationWillTerminate: {}
        )
        controller.beginSessionObservation()
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(displayChangeCount == 1)

        let model = makePresentationModel()
        let display = CommandWheelDisplaySnapshot(
            identifier: "display",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 580),
            scale: 2
        )
        controller.present(
            model: model,
            position: CommandWheelPosition(
                display: display,
                requestedCenter: CGPoint(x: 400, y: 300),
                actualCenter: CGPoint(x: 400, y: 300),
                contentFrame: CGRect(x: 178, y: 78, width: 444, height: 444),
                wasClamped: false
            ),
            activationBehavior: .holdAndRelease,
            frontmostProcessIdentifier: nil,
            onActivateSlot: { _ in },
            onActivateCenter: {},
            onKeyboardCommand: { _ in false }
        )
        await Task.yield()
        #expect(model.visualPhase == .visible)

        let panel = try #require(controller.currentPanel)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)

        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await Task.yield()
        #expect(displayChangeCount == 2)
        controller.dismiss()
        #expect(model.visualPhase == .dismissing)
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await Task.yield()
        #expect(displayChangeCount == 2)
        #expect(controller.currentPanel == nil)
        #expect(focus.processIdentifiers.isEmpty)
        #expect(activator.activationCount == 0)
        controller.tearDown()
    }

    @Test @MainActor
    func presentationModelProvidesStableSegmentSemantics() throws {
        let model = makePresentationModel()
        let segment = try #require(model.segment(at: 0))

        #expect(segment.accessibilityIdentifier.hasPrefix("command-wheel.segment."))
        #expect(segment.accessibilityLabel.contains("command"))
        #expect(segment.accessibilityValue(isSelected: true).contains("selected"))
        #expect(segment.accessibilityValue(isSelected: true).contains("available"))
        #expect(segment.accessibilityHint == "Runs this command.")
        #expect(model.centerAction == .cancel)
        #expect(model.contentSize == CGSize(width: 444, height: 444))
        #expect(model.selectableSlotIndices == [0])
    }

    @Test
    func contentFreezerUsesResolvedMetadataAndFreezesFrequentProviderOrder() async throws {
        let frequent = CommandID(rawValue: "test.frequent")
        let recent = CommandID(rawValue: "test.recent")
        let resolver = RuntimeCommandResolver(
            commands: [
                frequent: makeResolvedCommand(id: frequent, title: "Frequent", icon: "star"),
                recent: makeResolvedCommand(id: recent, title: "Recent", icon: "clock"),
            ]
        )
        let history = InMemoryCommandUsageHistory()
        await history.record(CommandExecutionRecord(
            commandID: frequent,
            source: .search,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 10)
        ))
        await history.record(CommandExecutionRecord(
            commandID: frequent,
            source: .search,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 20)
        ))
        await history.record(CommandExecutionRecord(
            commandID: recent,
            source: .search,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 30)
        ))

        var profile = CommandWheelDefaults.defaultProfile
        let pageID = profile.rootPageID
        let dynamicSegmentID = UUID()
        profile.pages = [
            CommandWheelPage(
                id: pageID,
                name: "Dynamic",
                segments: [
                    CommandWheelSegment(
                        id: dynamicSegmentID,
                        slotIndex: 0,
                        content: .dynamicProvider(
                            CommandWheelDynamicProviderReference(
                                providerID: CommandWheelDynamicProviderID.frequentCommands,
                                maximumResultCount: 2,
                                sortingMethod: .providerDefault,
                                emptyState: .showEmptySlots,
                                refreshStrategy: .onInvocation,
                                cachePolicy: .invocation
                            )
                        ),
                        customLabel: nil,
                        customIcon: nil
                    ),
                ]
            ),
        ]

        let frozen = try await DefaultCommandWheelContentFreezer(
            resolver: resolver,
            usageHistory: history
        ).freeze(profile: profile)
        let page = try #require(frozen.page(id: pageID))
        #expect(page.segments.map(\.slotIndex) == [0, 1])
        #expect(page.segments.map(\.title) == ["Frequent", "Recent"])
        #expect(page.segments.allSatisfy { $0.isDynamic })
        #expect(page.segments.allSatisfy { $0.sourceSegmentID == dynamicSegmentID })

        await history.record(CommandExecutionRecord(
            commandID: recent,
            source: .search,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 40)
        ))
        #expect(frozen.page(id: pageID)?.segments.map(\.title) == ["Frequent", "Recent"])
    }

    @Test
    func dynamicHistorySkipsNonReplayableParameterizedCommandsBeforeLimit() async throws {
        let parameterizedID = CommandID(rawValue: "test.parameterized")
        let firstReusableID = CommandID(rawValue: "test.reusable.first")
        let secondReusableID = CommandID(rawValue: "test.reusable.second")
        let registry = CommandRegistry()
        try await registry.register(CommandManifest(
            id: parameterizedID,
            title: "Needs Input",
            systemImage: "text.cursor",
            category: .productivity,
            mode: .action,
            arguments: [
                CommandArgument(
                    name: "input",
                    description: "Required invocation input",
                    isRequired: true
                ),
            ]
        ))
        try await registry.register(CommandManifest(
            id: firstReusableID,
            title: "Reusable One",
            systemImage: "1.circle",
            category: .productivity,
            mode: .action,
            arguments: [
                CommandArgument(
                    name: "input",
                    description: "Reusable default input",
                    isRequired: true,
                    defaultValue: .string("default-input")
                ),
            ]
        ))
        try await registry.register(CommandManifest(
            id: secondReusableID,
            title: "Reusable Two",
            systemImage: "2.circle",
            category: .productivity,
            mode: .action
        ))

        let history = InMemoryCommandUsageHistory()
        for timestamp in 1 ... 3 {
            await history.record(CommandExecutionRecord(
                commandID: parameterizedID,
                source: .search,
                outcome: .succeeded,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp))
            ))
        }
        for timestamp in 4 ... 5 {
            await history.record(CommandExecutionRecord(
                commandID: firstReusableID,
                source: .search,
                outcome: .succeeded,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp))
            ))
        }
        await history.record(CommandExecutionRecord(
            commandID: secondReusableID,
            source: .search,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 6)
        ))

        var profile = CommandWheelDefaults.defaultProfile
        let pageID = profile.rootPageID
        profile.pages = [
            CommandWheelPage(
                id: pageID,
                name: "Dynamic",
                segments: [
                    CommandWheelSegment(
                        id: UUID(),
                        slotIndex: 0,
                        content: .dynamicProvider(CommandWheelDynamicProviderReference(
                            providerID: CommandWheelDynamicProviderID.frequentCommands,
                            maximumResultCount: 2,
                            sortingMethod: .mostFrequent,
                            emptyState: .showEmptySlots,
                            refreshStrategy: .onInvocation,
                            cachePolicy: .invocation
                        )),
                        customLabel: nil,
                        customIcon: nil
                    ),
                ]
            ),
        ]

        let frozen = try await DefaultCommandWheelContentFreezer(
            resolver: registry,
            usageHistory: history
        ).freeze(profile: profile)
        let segments = try #require(frozen.page(id: pageID)?.segments)

        #expect(segments.map(\.title) == ["Reusable One", "Reusable Two"])
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.state == .available })
        if case .command(let reference) = segments[0].kind {
            #expect(reference.arguments["input"] == .string("default-input"))
        } else {
            Issue.record("Expected the defaulted parameterized command to remain replayable")
        }
    }

    @Test
    func dynamicProviderBoundsHistoryResolutionAndReusesSessionResolutions() async throws {
        let commandIDs = (0 ..< 120).map {
            CommandID(rawValue: "test.history.\($0)")
        }
        let resolver = RuntimeCommandResolver(
            commands: [:],
            missing: Set(commandIDs)
        )
        let history = InMemoryCommandUsageHistory()
        for (offset, commandID) in commandIDs.enumerated() {
            await history.record(CommandExecutionRecord(
                commandID: commandID,
                source: .search,
                outcome: .succeeded,
                timestamp: Date(timeIntervalSince1970: TimeInterval(offset))
            ))
        }

        var profile = CommandWheelDefaults.defaultProfile
        let rootPageID = profile.rootPageID
        let childPageID = UUID()
        let provider = CommandWheelDynamicProviderReference(
            providerID: CommandWheelDynamicProviderID.recentCommands,
            maximumResultCount: 1,
            sortingMethod: .mostRecent,
            emptyState: .showEmptySlots,
            refreshStrategy: .onInvocation,
            cachePolicy: .invocation
        )
        profile.pages = [
            CommandWheelPage(
                id: childPageID,
                name: "Child",
                segments: [
                    CommandWheelSegment(
                        id: UUID(),
                        slotIndex: 0,
                        content: .dynamicProvider(provider),
                        customLabel: nil,
                        customIcon: nil
                    ),
                ]
            ),
            CommandWheelPage(
                id: rootPageID,
                name: "Root",
                segments: [
                    CommandWheelSegment(
                        id: UUID(),
                        slotIndex: 0,
                        content: .dynamicProvider(provider),
                        customLabel: nil,
                        customIcon: nil
                    ),
                    CommandWheelSegment(
                        id: UUID(),
                        slotIndex: 1,
                        content: .submenu(pageID: childPageID),
                        customLabel: nil,
                        customIcon: nil
                    ),
                ]
            ),
        ]

        let frozen = try await DefaultCommandWheelContentFreezer(
            resolver: resolver,
            usageHistory: history
        ).freeze(profile: profile)

        #expect(frozen.page(id: rootPageID) != nil)
        #expect(frozen.page(id: childPageID) != nil)
        // A one-result provider receives the 32-candidate floor (never more than 96), and the
        // session cache prevents the child page from resolving those missing references again.
        #expect(await resolver.resolveCount == 32)
    }

    @Test
    func contentFreezerPreservesMissingAndUnavailableReferencesWithoutExecuting() async throws {
        let unavailableID = CommandID(rawValue: "test.unavailable")
        let missingID = CommandID(rawValue: "test.missing")
        let resolver = RuntimeCommandResolver(
            commands: [
                unavailableID: makeResolvedCommand(
                    id: unavailableID,
                    title: "Unavailable",
                    icon: "lock",
                    availability: .unavailable(.missingPermission(identifier: "test"))
                ),
            ],
            missing: [missingID]
        )
        var profile = CommandWheelDefaults.defaultProfile
        let pageID = profile.rootPageID
        profile.pages = [
            CommandWheelPage(
                id: pageID,
                name: "States",
                segments: [
                    CommandWheelSegment(
                        id: UUID(),
                        slotIndex: 0,
                        content: .command(CommandReference(commandID: unavailableID)),
                        customLabel: nil,
                        customIcon: nil
                    ),
                    CommandWheelSegment(
                        id: UUID(),
                        slotIndex: 1,
                        content: .command(CommandReference(commandID: missingID)),
                        customLabel: "Kept reference",
                        customIcon: nil
                    ),
                ]
            ),
        ]

        let page = try #require(
            try await DefaultCommandWheelContentFreezer(
                resolver: resolver,
                usageHistory: InMemoryCommandUsageHistory()
            ).freeze(profile: profile).page(id: pageID)
        )
        #expect(page.segments[0].state == .unavailable(.missingPermission(identifier: "test")))
        #expect(page.segments[0].systemImage == "lock")
        #expect(page.segments[1].state == .missing)
        #expect(page.segments[1].title == "Kept reference")
        #expect(await resolver.resolveCount == 2)
    }

    @Test
    func installedApplicationMetadataProvidesAXNameAndCustomIconTakesPrecedence() async throws {
        let application = InstalledApplication(
            bundleIdentifier: "com.example.RapidAccess",
            name: "Rapid Access",
            path: "/Applications/Rapid Access.app"
        )
        let applicationQuery = RuntimeInstalledApplicationQuery(applications: [application])
        let reference = BuiltInCommandReference.openInstalledApplication(
            bundleIdentifier: application.bundleIdentifier
        )
        let manifest = CommandManifest(
            id: BuiltInCommandID.openInstalledApplication,
            title: "Open Application",
            subtitle: "Launch an installed application",
            systemImage: "app",
            category: .productivity,
            mode: .action,
            arguments: [
                CommandArgument(
                    name: BuiltInCommandArgumentName.bundleIdentifier,
                    description: "Installed application bundle identifier",
                    isRequired: true
                ),
            ]
        )
        let resolver = RuntimeCommandResolver(commands: [
            manifest.id: ResolvedCommand(
                reference: reference,
                manifest: manifest,
                availability: .available
            ),
        ])
        var profile = CommandWheelDefaults.defaultProfile
        profile.pages[0].segments[0].content = .command(reference)
        profile.pages[0].segments[0].customLabel = nil
        profile.pages[0].segments[0].customIcon = nil

        let nativePage = try #require(
            try await DefaultCommandWheelContentFreezer(
                resolver: resolver,
                usageHistory: InMemoryCommandUsageHistory(),
                installedApplicationQuery: applicationQuery
            ).freeze(profile: profile).page(id: profile.rootPageID)
        )
        let nativeSegment = try #require(
            nativePage.segments.first(where: { $0.slotIndex == 0 })
        )
        #expect(nativeSegment.title == application.name)
        #expect(nativeSegment.applicationIconPath == application.path)
        #expect(nativeSegment.usesCustomIcon == false)
        #expect(nativeSegment.kind == .command(reference))
        #expect(nativeSegment.accessibilityLabel.contains(application.name))
        #expect(nativeSegment.accessibilityLabel.contains("selected") == false)
        #expect(nativeSegment.accessibilityValue(isSelected: true) == "selected, available")

        profile.pages[0].segments[0].customIcon = CommandWheelIconOverride(
            systemSymbolName: "star.fill"
        )
        let customPage = try #require(
            try await DefaultCommandWheelContentFreezer(
                resolver: resolver,
                usageHistory: InMemoryCommandUsageHistory(),
                installedApplicationQuery: applicationQuery
            ).freeze(profile: profile).page(id: profile.rootPageID)
        )
        let customSegment = try #require(
            customPage.segments.first(where: { $0.slotIndex == 0 })
        )
        #expect(customSegment.title == application.name)
        #expect(customSegment.systemImage == "star.fill")
        #expect(customSegment.usesCustomIcon)
        #expect(customSegment.applicationIconPath == nil)
        #expect(await applicationQuery.queryCount == 2)
    }

    @Test
    func contentFreezerDoesNotQueryApplicationsWithoutApplicationReferences() async throws {
        let applicationQuery = RuntimeInstalledApplicationQuery(applications: [])
        _ = try await DefaultCommandWheelContentFreezer(
            resolver: RuntimeCommandResolver(commands: [:]),
            usageHistory: InMemoryCommandUsageHistory(),
            installedApplicationQuery: applicationQuery
        ).freeze(profile: CommandWheelDefaults.defaultProfile)

        #expect(await applicationQuery.queryCount == 0)
    }
}

@MainActor
private struct RuntimeCoordinatorFixture {
    let coordinator: CommandWheelCoordinator
    let profile: CommandWheelProfile
    let commandID: CommandID
    let segmentID: UUID
    let contextProvider: InMemoryFrontmostApplicationContextProvider
    let pointer: RuntimePointerProvider
    let pointerScheduler: RuntimeTimerScheduler
    let input: CommandWheelInputLifecycle
    let monitors: RuntimeEventMonitorManager
    let display: RuntimeDisplayResolver
    let window: RuntimeWindowPresenter
    let executor: RuntimeSharedCommandExecutor
    let childPageID: UUID?
}

@MainActor
private func makeCoordinatorFixture(
    activationBehavior: CommandWheelActivationBehavior,
    includesSubmenu: Bool = false,
    preparationGate: RuntimeAsyncGate? = nil
) -> RuntimeCoordinatorFixture {
    var profile = CommandWheelDefaults.defaultProfile
    profile.activationBehavior = activationBehavior
    profile.placement = .cursor
    if includesSubmenu {
        profile.interaction.submenuActivationBehavior = .directionalContinuation
    }
    let commandID = CommandID(rawValue: "test.runtime")
    let rootPage = profile.pages.first
    let rootSegmentID = rootPage?.segments.first?.id ?? UUID()
    let childPageID = includesSubmenu ? UUID() : nil
    let segmentID = includesSubmenu ? UUID() : rootSegmentID
    let commandSegment = CommandWheelPresentedSegment(
        sourceSegmentID: segmentID,
        pageID: childPageID ?? profile.rootPageID,
        slotIndex: 0,
        kind: .command(CommandReference(commandID: commandID)),
        state: .available,
        title: "Runtime command",
        subtitle: nil,
        systemImage: "bolt",
        isDynamic: false
    )
    let rootSegment = CommandWheelPresentedSegment(
        sourceSegmentID: rootSegmentID,
        pageID: profile.rootPageID,
        slotIndex: 0,
        kind: childPageID.map { .submenu(pageID: $0) }
            ?? .command(CommandReference(commandID: commandID)),
        state: .available,
        title: childPageID == nil ? "Runtime command" : "Child",
        subtitle: nil,
        systemImage: childPageID == nil ? "bolt" : "square.stack.3d.up",
        isDynamic: false
    )
    var pagesByID = [
        profile.rootPageID: CommandWheelFrozenPage(
            id: profile.rootPageID,
            name: "Main",
            segments: [rootSegment]
        ),
    ]
    var parentPageByID = [UUID: UUID]()
    if let childPageID {
        profile.pages.append(CommandWheelPage(id: childPageID, name: "Child", segments: []))
        pagesByID[childPageID] = CommandWheelFrozenPage(
            id: childPageID,
            name: "Child",
            segments: [commandSegment]
        )
        parentPageByID[childPageID] = profile.rootPageID
    }
    let frozen = CommandWheelFrozenContent(
        pagesByID: pagesByID,
        parentPageByID: parentPageByID
    )
    let pointer = RuntimePointerProvider(location: CGPoint(x: 500, y: 500))
    let pointerScheduler = RuntimeTimerScheduler()
    let monitors = RuntimeEventMonitorManager()
    let input = CommandWheelInputLifecycle(
        pointerSampler: CommandWheelPointerSampler(
            pointerProvider: pointer,
            timerScheduler: pointerScheduler
        ),
        eventMonitors: monitors
    )
    let display = RuntimeDisplayResolver()
    let window = RuntimeWindowPresenter()
    let executor = RuntimeSharedCommandExecutor()
    let contextProvider = InMemoryFrontmostApplicationContextProvider(
        context: FrontmostApplicationContext(
            processIdentifier: 77,
            bundleIdentifier: "com.example.frontmost",
            localizedName: "Frontmost"
        )
    )
    let configuration = CommandWheelConfiguration(
        isEnabled: true,
        contextAwareProfileSelectionEnabled: false,
        defaultProfileID: profile.id,
        profiles: [profile]
    )
    let coordinator = CommandWheelCoordinator(
        configuration: configuration,
        frontmostContextProvider: contextProvider,
        contentFreezer: RuntimeContentFreezer(content: frozen, gate: preparationGate),
        commandCoordinator: executor,
        displayResolver: display,
        windowPresenter: window,
        inputLifecycle: input,
        timerScheduler: RuntimeTimerScheduler(),
        now: { Date(timeIntervalSince1970: 123) }
    )
    return RuntimeCoordinatorFixture(
        coordinator: coordinator,
        profile: profile,
        commandID: commandID,
        segmentID: segmentID,
        contextProvider: contextProvider,
        pointer: pointer,
        pointerScheduler: pointerScheduler,
        input: input,
        monitors: monitors,
        display: display,
        window: window,
        executor: executor,
        childPageID: childPageID
    )
}

@MainActor
private func waitForPresentation(_ coordinator: CommandWheelCoordinator) async {
    for _ in 0 ..< 100 where coordinator.presentationModel == nil {
        await Task.yield()
    }
    #expect(coordinator.presentationModel != nil)
}

@MainActor
private func waitForSessionEnd(_ coordinator: CommandWheelCoordinator) async {
    for _ in 0 ..< 100 where coordinator.activeSessionToken != nil {
        await Task.yield()
    }
    #expect(coordinator.activeSessionToken == nil)
}

private func waitForExecutionCount(
    _ count: Int,
    executor: RuntimeSharedCommandExecutor
) async {
    for _ in 0 ..< 100 {
        if await executor.calls.count >= count { return }
        await Task.yield()
    }
    Issue.record("Shared execution did not receive the expected call")
}

@MainActor
private func makePresentationModel() -> CommandWheelPresentationModel {
    let profile = CommandWheelDefaults.defaultProfile
    let segment = CommandWheelPresentedSegment(
        sourceSegmentID: UUID(),
        pageID: profile.rootPageID,
        slotIndex: 0,
        kind: .command(CommandReference(commandID: CommandID(rawValue: "test.presentation"))),
        state: .available,
        title: "Presentation",
        subtitle: "Subtitle",
        systemImage: "sparkles",
        isDynamic: false
    )
    return CommandWheelPresentationModel(
        profileID: profile.id,
        profileName: profile.name,
        pageID: profile.rootPageID,
        pageName: "Main",
        appearance: profile.appearance,
        interaction: profile.interaction,
        segments: [segment]
    )
}

private func makeResolvedCommand(
    id: CommandID,
    title: String,
    icon: String,
    availability: CommandAvailability = .available
) -> ResolvedCommand {
    ResolvedCommand(
        reference: CommandReference(commandID: id),
        manifest: CommandManifest(
            id: id,
            title: title,
            systemImage: icon,
            category: .productivity,
            mode: .action
        ),
        availability: availability
    )
}

private nonisolated struct RuntimeContentFreezer: CommandWheelContentFreezing {
    let content: CommandWheelFrozenContent
    let gate: RuntimeAsyncGate?

    init(content: CommandWheelFrozenContent, gate: RuntimeAsyncGate? = nil) {
        self.content = content
        self.gate = gate
    }

    func freeze(profile _: CommandWheelProfile) async throws -> CommandWheelFrozenContent {
        await gate?.wait()
        return content
    }
}

private actor RuntimeAsyncGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard isOpen == false else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard isOpen == false else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor RuntimeSharedCommandExecutor: SharedCommandExecutionCoordinating {
    struct Call: Sendable {
        let reference: CommandReference
        let context: CommandInvocationContext
    }

    private(set) var calls = [Call]()

    func execute(
        reference: CommandReference,
        context: CommandInvocationContext
    ) async throws -> CommandResult {
        calls.append(Call(reference: reference, context: context))
        return .success(message: nil)
    }
}

@MainActor
private final class RuntimeDisplayResolver: CommandWheelDisplayResolving {
    var isConnected = true
    let display = CommandWheelDisplaySnapshot(
        identifier: "display-main",
        frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
        scale: 2
    )

    func capture(pointerLocation _: CGPoint) -> CommandWheelDisplayEnvironmentSnapshot {
        CommandWheelDisplayEnvironmentSnapshot(
            sessionID: UUID(),
            displays: isConnected ? [display] : [],
            activeDisplayIdentifier: isConnected ? display.identifier : nil
        )
    }

    func isDisplayConnected(identifier: String) -> Bool {
        isConnected && identifier == display.identifier
    }
}

@MainActor
private final class RuntimeWindowPresenter: CommandWheelWindowPresenting {
    private(set) var isPresented = false
    private(set) var isObservingLifecycle = false
    private(set) var panelFrame: CGRect?
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var pressedSlotAtDismiss: Int?
    private var presentedModel: CommandWheelPresentationModel?
    private var onDisplayConfigurationChanged: (() -> Void)?
    private var onActiveSpaceChanged: (() -> Void)?
    private var onFrontmostApplicationChanged: ((Int32?) -> Void)?
    private var onApplicationWillTerminate: (() -> Void)?

    func setLifecycleHandlers(
        displayConfigurationChanged: @escaping () -> Void,
        activeSpaceChanged: @escaping () -> Void,
        frontmostApplicationChanged: @escaping (Int32?) -> Void,
        applicationWillTerminate: @escaping () -> Void
    ) {
        onDisplayConfigurationChanged = displayConfigurationChanged
        onActiveSpaceChanged = activeSpaceChanged
        onFrontmostApplicationChanged = frontmostApplicationChanged
        onApplicationWillTerminate = applicationWillTerminate
    }

    func beginSessionObservation() {
        isObservingLifecycle = true
    }

    func endSessionObservation() {
        isObservingLifecycle = false
    }

    func present(
        model: CommandWheelPresentationModel,
        position: CommandWheelPosition,
        activationBehavior _: CommandWheelActivationBehavior,
        frontmostProcessIdentifier _: Int32?,
        onActivateSlot _: @escaping (Int) -> Void,
        onActivateCenter _: @escaping () -> Void,
        onKeyboardCommand _: @escaping (CommandWheelKeyboardCommand) -> Bool
    ) {
        beginSessionObservation()
        isPresented = true
        presentedModel = model
        panelFrame = position.contentFrame
        presentCount += 1
    }

    func dismiss() {
        if isPresented {
            dismissCount += 1
            pressedSlotAtDismiss = presentedModel?.pressedSlotIndex
        }
        isPresented = false
        panelFrame = nil
        presentedModel = nil
        endSessionObservation()
    }

    func tearDown() {
        dismiss()
        onDisplayConfigurationChanged = nil
        onActiveSpaceChanged = nil
        onFrontmostApplicationChanged = nil
        onApplicationWillTerminate = nil
    }

    func fireDisplayConfigurationChanged() {
        guard isObservingLifecycle else { return }
        onDisplayConfigurationChanged?()
    }

    func fireActiveSpaceChanged() {
        guard isObservingLifecycle else { return }
        onActiveSpaceChanged?()
    }

    func fireApplicationWillTerminate() {
        guard isObservingLifecycle else { return }
        onApplicationWillTerminate?()
    }

    func fireFrontmostApplicationChanged(_ processIdentifier: Int32?) {
        guard isObservingLifecycle else { return }
        onFrontmostApplicationChanged?(processIdentifier)
    }
}

@MainActor
private final class RuntimePointerProvider: CommandWheelPointerLocationProviding {
    var location: CGPoint
    var currentPointerLocation: CGPoint { location }

    init(location: CGPoint) {
        self.location = location
    }
}

@MainActor
private final class RuntimeScheduledTask: CommandWheelScheduledTask {
    let action: @MainActor () -> Void
    private(set) var isCancelled = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func fire() {
        if isCancelled == false { action() }
    }
}

@MainActor
private final class RuntimeTimerScheduler: CommandWheelTimerScheduling {
    private(set) var tasks = [RuntimeScheduledTask]()

    func scheduleRepeating(
        every _: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any CommandWheelScheduledTask {
        append(action)
    }

    func scheduleOnce(
        after _: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any CommandWheelScheduledTask {
        append(action)
    }

    private func append(
        _ action: @escaping @MainActor () -> Void
    ) -> RuntimeScheduledTask {
        let task = RuntimeScheduledTask(action: action)
        tasks.append(task)
        return task
    }
}

@MainActor
private final class RuntimeEventMonitorManager: CommandWheelEventMonitorManaging {
    private(set) var installCount = 0
    private(set) var removeCount = 0
    private var localHandler:
        ((CommandWheelClickEvent) -> CommandWheelLocalClickDisposition)?
    private var globalHandler: ((CommandWheelClickEvent) -> Void)?

    var hasMonitors: Bool { localHandler != nil || globalHandler != nil }

    func install(
        localHandler: @escaping (CommandWheelClickEvent) -> CommandWheelLocalClickDisposition,
        globalHandler: @escaping (CommandWheelClickEvent) -> Void
    ) {
        installCount += 1
        self.localHandler = localHandler
        self.globalHandler = globalHandler
    }

    func removeAll() {
        removeCount += 1
        localHandler = nil
        globalHandler = nil
    }

    func sendLocal(_ event: CommandWheelClickEvent) -> CommandWheelLocalClickDisposition {
        localHandler?(event) ?? .passThrough
    }
}

@MainActor
private final class RuntimeFocusRestorer: CommandWheelFocusRestoring {
    private(set) var processIdentifiers = [Int32]()

    func restoreFocus(to processIdentifier: Int32) {
        processIdentifiers.append(processIdentifier)
    }
}

@MainActor
private final class RuntimeApplicationActivator: CommandWheelApplicationActivating {
    private(set) var activationCount = 0

    func activateForKeyboardInput() {
        activationCount += 1
    }
}

private actor RuntimeCommandResolver: CommandResolving {
    let commands: [CommandID: ResolvedCommand]
    let missing: Set<CommandID>
    private(set) var resolveCount = 0

    init(
        commands: [CommandID: ResolvedCommand],
        missing: Set<CommandID> = []
    ) {
        self.commands = commands
        self.missing = missing
    }

    func resolve(reference: CommandReference) async throws -> ResolvedCommand {
        resolveCount += 1
        if missing.contains(reference.commandID) {
            throw CommandRegistryError.commandNotFound(reference.commandID)
        }
        guard let command = commands[reference.commandID] else {
            throw CommandRegistryError.commandNotFound(reference.commandID)
        }
        return ResolvedCommand(
            reference: reference,
            manifest: command.manifest,
            availability: command.availability
        )
    }
}

private actor RuntimeInstalledApplicationQuery: InstalledApplicationQuerying {
    let applications: [InstalledApplication]
    private(set) var queryCount = 0

    init(applications: [InstalledApplication]) {
        self.applications = applications
    }

    func installedApplications() async -> [InstalledApplication] {
        queryCount += 1
        return applications
    }
}
