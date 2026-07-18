import CommandKit
import CoreGraphics
import Foundation
import Infrastructure

/// Existing app result/status surfaces can implement this seam without teaching the wheel how to
/// present command-specific success, permission, or failure UI.
@MainActor
protocol CommandWheelResultFeedbackHandling: AnyObject {
    func commandWheelDidComplete(
        result: CommandResult,
        context: CommandInvocationContext
    )

    func commandWheelDidFail(
        error: any Error,
        context: CommandInvocationContext
    )
}

@MainActor
final class NullCommandWheelResultFeedbackHandler: CommandWheelResultFeedbackHandling {
    func commandWheelDidComplete(
        result _: CommandResult,
        context _: CommandInvocationContext
    ) {}

    func commandWheelDidFail(
        error _: any Error,
        context _: CommandInvocationContext
    ) {}
}

/// Owns one active presentation/input session while allowing already-dispatched shared commands
/// to complete independently. All native UI and mutable gesture state remain on the main actor.
@MainActor
final class CommandWheelCoordinator {
    private var configuration: CommandWheelConfiguration
    private let frontmostContextProvider: any FrontmostApplicationContextProviding
    private let contentFreezer: any CommandWheelContentFreezing
    private let commandCoordinator: any SharedCommandExecutionCoordinating
    private let displayResolver: any CommandWheelDisplayResolving
    private let windowPresenter: any CommandWheelWindowPresenting
    private let inputLifecycle: CommandWheelInputLifecycle
    private let timerScheduler: any CommandWheelTimerScheduling
    private let resultFeedback: any CommandWheelResultFeedbackHandling
    private let now: () -> Date
    private let makeUUID: () -> UUID

    private let stateMachine: CommandWheelSessionStateMachine
    private var activeSession: ActiveSession?
    private var submenuDwellTask: (any CommandWheelScheduledTask)?
    private var executionTasks = [UUID: Task<Void, Never>]()

    private(set) var presentationModel: CommandWheelPresentationModel?

    var activeSessionToken: CommandWheelSessionToken? {
        activeSession?.token
    }

    var presentationState: CommandWheelPresentationState {
        stateMachine.state
    }

    init(
        configuration: CommandWheelConfiguration,
        frontmostContextProvider: any FrontmostApplicationContextProviding,
        contentFreezer: any CommandWheelContentFreezing,
        commandCoordinator: any SharedCommandExecutionCoordinating,
        displayResolver: any CommandWheelDisplayResolving =
            NSScreenCommandWheelDisplayResolver(),
        windowPresenter: any CommandWheelWindowPresenting =
            CommandWheelWindowController(),
        inputLifecycle: CommandWheelInputLifecycle = CommandWheelInputLifecycle(),
        timerScheduler: any CommandWheelTimerScheduling =
            FoundationCommandWheelTimerScheduler(),
        resultFeedback: any CommandWheelResultFeedbackHandling =
            NullCommandWheelResultFeedbackHandler(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.configuration = configuration
        self.frontmostContextProvider = frontmostContextProvider
        self.contentFreezer = contentFreezer
        self.commandCoordinator = commandCoordinator
        self.displayResolver = displayResolver
        self.windowPresenter = windowPresenter
        self.inputLifecycle = inputLifecycle
        self.timerScheduler = timerScheduler
        self.resultFeedback = resultFeedback
        self.now = now
        self.makeUUID = makeUUID
        stateMachine = CommandWheelSessionStateMachine(makeUUID: makeUUID)

        windowPresenter.setLifecycleHandlers(
            displayConfigurationChanged: { [weak self] in
                self?.displayConfigurationChanged()
            },
            activeSpaceChanged: { [weak self] in
                self?.cancelActiveSession(.contextLost)
            },
            frontmostApplicationChanged: { [weak self] processIdentifier in
                self?.frontmostApplicationChanged(processIdentifier)
            },
            applicationWillTerminate: { [weak self] in
                self?.applicationWillTerminate()
            }
        )
    }

    convenience init(
        configuration: CommandWheelConfiguration,
        frontmostContextProvider: any FrontmostApplicationContextProviding,
        resolver: any CommandResolving,
        usageHistory: any CommandUsageHistoryStoring,
        installedApplicationQuery: any InstalledApplicationQuerying =
            InMemoryInstalledApplicationQuery(),
        commandCoordinator: any SharedCommandExecutionCoordinating,
        resultFeedback: any CommandWheelResultFeedbackHandling =
            NullCommandWheelResultFeedbackHandler()
    ) {
        self.init(
            configuration: configuration,
            frontmostContextProvider: frontmostContextProvider,
            contentFreezer: DefaultCommandWheelContentFreezer(
                resolver: resolver,
                usageHistory: usageHistory,
                installedApplicationQuery: installedApplicationQuery
            ),
            commandCoordinator: commandCoordinator,
            resultFeedback: resultFeedback
        )
    }

    /// Replaces the cached, already-validated settings snapshot. Disk I/O never occurs here.
    func updateConfiguration(_ configuration: CommandWheelConfiguration) {
        self.configuration = configuration
        guard let activeSession else { return }
        let profileStillAvailable = configuration.profiles.contains {
            $0.id == activeSession.profile.id && $0.isEnabled
        }
        if configuration.isEnabled == false || profileStillAvailable == false {
            cancelActiveSession(.featureDisabled)
        }
    }

    /// Called for the owning global-shortcut press. The frontmost app, pointer, and screens are
    /// captured synchronously before any panel can change focus.
    @discardableResult
    func shortcutPressed(
        explicitProfileID: UUID?,
        allowsContextOverride: Bool = false
    ) -> CommandWheelSessionToken? {
        guard configuration.isEnabled else { return nil }

        if let activeSession,
           activeSession.profile.activationBehavior == .toggle,
           explicitProfileID == nil || activeSession.profile.id == explicitProfileID {
            cancelActiveSession(.explicit)
            return nil
        }
        guard activeSession == nil else { return nil }

        windowPresenter.beginSessionObservation()
        var shouldEndSessionObservation = true
        defer {
            if shouldEndSessionObservation {
                windowPresenter.endSessionObservation()
            }
        }

        let frontmostContext = frontmostContextProvider.snapshot()
        guard let selection = CommandWheelProfileSelector.resolve(
            configuration: configuration,
            explicitProfileID: explicitProfileID,
            allowsContextOverride: allowsContextOverride,
            frontmostApplicationBundleIdentifier: frontmostContext?.bundleIdentifier
        ),
        let profile = configuration.profiles.first(where: { $0.id == selection.profileID }),
        profile.isEnabled,
        profile.pages.contains(where: { $0.id == profile.rootPageID }) else {
            return nil
        }

        guard case .started(let token) = stateMachine.shortcutPressed(
            profileID: profile.id,
            rootPageID: profile.rootPageID
        ) else {
            return nil
        }

        let pointerLocation = inputLifecycle.currentPointerLocation
        let displayEnvironment = displayResolver.capture(pointerLocation: pointerLocation)
        let contentSize = Self.contentSize(for: profile.appearance)
        guard let position = CommandWheelPositioningEngine.position(
            placement: profile.placement,
            pointerLocation: pointerLocation,
            displays: displayEnvironment.displays,
            activeDisplayIdentifier: displayEnvironment.activeDisplayIdentifier,
            contentSize: contentSize
        ) else {
            failAndDismiss(.presentationFailed, token: token)
            return token
        }

        let session = ActiveSession(
            token: token,
            profile: profile,
            frontmostContext: frontmostContext,
            displayEnvironment: displayEnvironment,
            position: position,
            invocationDate: now(),
            selectionEngine: CommandWheelSelectionEngine(
                interaction: profile.interaction,
                startAngleDegrees: profile.appearance.startAngleDegrees
            )
        )
        activeSession = session
        shouldEndSessionObservation = false
        prepareContent(for: session)
        return token
    }

    /// Hold-mode key-up. Toggle sessions intentionally ignore release and remain visible.
    func shortcutReleased(sessionToken: CommandWheelSessionToken) {
        guard let activeSession, activeSession.token == sessionToken else { return }
        guard activeSession.profile.activationBehavior == .holdAndRelease else { return }

        if case .preparing = stateMachine.state {
            // Resolver latency must not turn a memorized fast flick into a cancellation. Keep the
            // final physical pointer sample and resolve it exactly once when preparation finishes.
            activeSession.pendingReleaseLocation = inputLifecycle.currentPointerLocation
            return
        }

        if inputLifecycle.isActive {
            inputLifecycle.sampleFinalAndStop()
        }
        completeHoldRelease(session: activeSession)
    }

    private func completeHoldRelease(session activeSession: ActiveSession) {
        guard let segment = presentationModel?.selectedSegment,
              case .command = segment.kind,
              segment.isSelectable else {
            _ = stateMachine.shortcutReleased(sessionToken: activeSession.token)
            completeDismissal(token: activeSession.token)
            return
        }

        presentationModel?.pressedSlotIndex = segment.slotIndex
        _ = stateMachine.shortcutReleased(sessionToken: activeSession.token)
        dispatchExecution(segment, session: activeSession)
    }

    func shortcutCancelled(sessionToken: CommandWheelSessionToken) {
        guard activeSession?.token == sessionToken else { return }
        cancelActiveSession(.shortcutInvalidated)
    }

    func activateSlot(_ slotIndex: Int) {
        guard let model = presentationModel,
              let segment = model.segment(at: slotIndex),
              segment.isSelectable else {
            return
        }
        selectSlotFromKeyboard(slotIndex)
        activate(segment: segment)
    }

    func activateCenter() {
        guard let activeSession else { return }
        if activeSession.pageStack.count > 1 {
            transitionBack(session: activeSession)
        } else {
            cancelActiveSession(.explicit)
        }
    }

    @discardableResult
    func handleKeyboardCommand(_ command: CommandWheelKeyboardCommand) -> Bool {
        guard let activeSession,
              activeSession.profile.activationBehavior == .toggle,
              activeSession.profile.interaction.allowsKeyboardSelection,
              let model = presentationModel else {
            return false
        }

        switch command {
        case .cancel:
            activateCenter()
        case .activate:
            guard let segment = model.selectedSegment else { return true }
            activate(segment: segment)
        case .next, .previous:
            let direction: CommandWheelKeyboardDirection = command == .next ? .next : .previous
            let slot = CommandWheelKeyboardSelection.movedSelection(
                from: model.selectedSlotIndex,
                direction: direction,
                slotCount: activeSession.profile.interaction.visibleSlotCount,
                selectableSlotIndices: model.selectableSlotIndices
            )
            if let slot { selectSlotFromKeyboard(slot) }
        case .selectVisibleSlot(let slot):
            if model.selectableSlotIndices.contains(slot) {
                selectSlotFromKeyboard(slot)
            }
        }
        return true
    }

    /// Explicit application shutdown hook. This is the primary resource cleanup path.
    func tearDown() {
        if activeSession != nil {
            cancelActiveSession(.applicationTerminating)
        } else {
            inputLifecycle.stop()
            windowPresenter.dismiss()
        }
        for task in executionTasks.values { task.cancel() }
        executionTasks.removeAll()
        windowPresenter.tearDown()
    }

    private func prepareContent(for session: ActiveSession) {
        let taskID = CommandWheelProviderTaskID(rawValue: makeUUID())
        let freezer = contentFreezer
        let profile = session.profile
        let token = session.token
        let task = Task { [weak self] in
            do {
                let frozen = try await freezer.freeze(profile: profile)
                try Task.checkCancellation()
                self?.completePreparation(frozen, taskID: taskID, token: token)
            } catch is CancellationError {
                self?.stateMachine.providerTaskCompleted(id: taskID, sessionToken: token)
            } catch {
                self?.stateMachine.providerTaskCompleted(id: taskID, sessionToken: token)
                self?.failAndDismiss(.providerFailed, token: token)
            }
        }
        _ = stateMachine.registerProviderTask(task, id: taskID, sessionToken: token)
    }

    private func completePreparation(
        _ frozen: CommandWheelFrozenContent,
        taskID: CommandWheelProviderTaskID,
        token: CommandWheelSessionToken
    ) {
        _ = stateMachine.providerTaskCompleted(id: taskID, sessionToken: token)
        guard let activeSession,
              activeSession.token == token,
              let rootPage = frozen.page(id: activeSession.profile.rootPageID),
              case .preparing = stateMachine.state else {
            return
        }

        guard frontmostContextProvider.snapshot()?.processIdentifier
            == activeSession.frontmostContext?.processIdentifier else {
            cancelActiveSession(.contextLost)
            return
        }

        let currentDisplayEnvironment = displayResolver.capture(
            pointerLocation: inputLifecycle.currentPointerLocation
        )
        guard currentDisplayEnvironment.displays == activeSession.displayEnvironment.displays else {
            cancelActiveSession(.displayUnavailable)
            return
        }

        activeSession.frozenContent = frozen
        activeSession.pageStack = [rootPage.id]

        let model = CommandWheelPresentationModel(
            profileID: activeSession.profile.id,
            profileName: activeSession.profile.name,
            pageID: rootPage.id,
            pageName: rootPage.name,
            appearance: activeSession.profile.appearance,
            interaction: activeSession.profile.interaction,
            segments: rootPage.segments
        )
        presentationModel = model

        guard case .applied = stateMachine.presentationBegan(sessionToken: token) else { return }
        guard case .applied = stateMachine.trackingBegan(sessionToken: token) else {
            failAndDismiss(.invalidTransition, token: token)
            return
        }

        if let pendingReleaseLocation = activeSession.pendingReleaseLocation {
            processPointer(CommandWheelPointerSample(
                location: pendingReleaseLocation,
                isFinal: true
            ))
            completeHoldRelease(session: activeSession)
            return
        }

        windowPresenter.present(
            model: model,
            position: activeSession.position,
            activationBehavior: activeSession.profile.activationBehavior,
            frontmostProcessIdentifier: activeSession.frontmostContext?.processIdentifier,
            onActivateSlot: { [weak self] slotIndex in self?.activateSlot(slotIndex) },
            onActivateCenter: { [weak self] in self?.activateCenter() },
            onKeyboardCommand: { [weak self] command in
                self?.handleKeyboardCommand(command) ?? false
            }
        )

        let mode: CommandWheelInputMode = activeSession.profile.activationBehavior == .toggle
            ? .toggle
            : .holdAndRelease
        inputLifecycle.start(
            mode: mode,
            panelFrame: { [weak windowPresenter] in windowPresenter?.panelFrame },
            interactiveRegionContains: { [weak self] location in
                self?.isInsideVisibleWheel(location) ?? false
            },
            onPointerSample: { [weak self] sample in self?.processPointer(sample) },
            onInsideClick: { [weak self] location in self?.handleInsideClick(location) },
            onOutsideClick: { [weak self] in self?.cancelActiveSession(.explicit) }
        )
    }

    private func processPointer(_ sample: CommandWheelPointerSample) {
        guard let activeSession,
              let model = presentationModel,
              model.isTransitioning == false else {
            return
        }

        let update = activeSession.selectionEngine.update(
            pointerLocation: sample.location,
            actualCenter: activeSession.position.actualCenter,
            selectableSlotIndices: model.selectableSlotIndices,
            isFinalSample: sample.isFinal
        )
        model.selectedSlotIndex = update.selection?.slotIndex
        _ = stateMachine.updateSelection(update.selection, sessionToken: activeSession.token)

        if update.hitTest.region == .selection || update.hitTest.region == .submenuActivation {
            activeSession.hasMovedOutwardOnCurrentPage = true
        }
        if update.hitTest.region == .deadZone,
           activeSession.hasMovedOutwardOnCurrentPage,
           activeSession.pageStack.count > 1 {
            transitionBack(session: activeSession)
            return
        }

        guard let selectedSlot = update.selection?.slotIndex,
              let selectedSegment = model.segment(at: selectedSlot),
              case .submenu(let pageID) = selectedSegment.kind else {
            cancelSubmenuDwell()
            return
        }

        switch activeSession.profile.interaction.submenuActivationBehavior {
        case .directionalContinuation:
            cancelSubmenuDwell()
            if update.selection?.reachedSubmenuActivationRadius == true {
                transition(to: pageID, session: activeSession)
            }
        case .dwell:
            if update.change != .unchanged {
                scheduleSubmenuDwell(
                    slotIndex: selectedSlot,
                    pageID: pageID,
                    session: activeSession
                )
            }
        case .clickOnly, .disabled:
            cancelSubmenuDwell()
        }
    }

    private func handleInsideClick(_ location: CGPoint) {
        guard let activeSession else { return }
        let distance = activeSession.selectionEngine.geometry.distance(
            from: activeSession.position.actualCenter,
            to: location
        )
        guard distance <= activeSession.profile.appearance.wheelRadius else {
            cancelActiveSession(.explicit)
            return
        }
        if distance < activeSession.profile.interaction.deadZoneRadius {
            activateCenter()
            return
        }
        guard activeSession.profile.interaction.allowsClickSelection else { return }
        processPointer(CommandWheelPointerSample(location: location, isFinal: true))
        if let segment = presentationModel?.selectedSegment {
            activate(segment: segment)
        }
    }

    private func activate(segment: CommandWheelPresentedSegment) {
        guard let activeSession, segment.isSelectable else { return }
        switch segment.kind {
        case .command:
            guard case .applied = stateMachine.requestExecution(
                slotIndex: segment.slotIndex,
                sessionToken: activeSession.token
            ) else {
                return
            }
            presentationModel?.pressedSlotIndex = segment.slotIndex
            dispatchExecution(segment, session: activeSession)
        case .submenu(let pageID):
            transition(to: pageID, session: activeSession)
        case .empty:
            break
        }
    }

    private func selectSlotFromKeyboard(_ slotIndex: Int) {
        guard let activeSession,
              let model = presentationModel,
              model.selectableSlotIndices.contains(slotIndex),
              let angle = activeSession.selectionEngine.geometry.slotCenterAngleDegrees(slotIndex)
        else {
            return
        }
        cancelSubmenuDwell()
        let absoluteAngle = angle + activeSession.profile.appearance.startAngleDegrees
        let radians = absoluteAngle * .pi / 180
        let radius = max(
            activeSession.profile.interaction.selectionRadius,
            activeSession.profile.interaction.deadZoneRadius + 1
        )
        let point = CGPoint(
            x: activeSession.position.actualCenter.x + CGFloat(sin(radians) * radius),
            y: activeSession.position.actualCenter.y + CGFloat(cos(radians) * radius)
        )
        let update = activeSession.selectionEngine.update(
            pointerLocation: point,
            actualCenter: activeSession.position.actualCenter,
            selectableSlotIndices: model.selectableSlotIndices,
            isFinalSample: true
        )
        model.selectedSlotIndex = update.selection?.slotIndex
        _ = stateMachine.updateSelection(update.selection, sessionToken: activeSession.token)
    }

    private func transition(to pageID: UUID, session: ActiveSession) {
        guard let frozenPage = session.frozenContent?.page(id: pageID),
              let model = presentationModel,
              model.pageID != pageID,
              case .applied = stateMachine.beginPageTransition(
                  to: pageID,
                  sessionToken: session.token
              ) else {
            return
        }
        cancelSubmenuDwell()
        model.isTransitioning = true
        session.pageStack.append(pageID)
        session.selectionEngine.reset()
        session.hasMovedOutwardOnCurrentPage = false
        model.replacePage(
            pageID: frozenPage.id,
            pageName: frozenPage.name,
            pageDepth: session.pageStack.count - 1,
            segments: frozenPage.segments
        )
        model.isTransitioning = false
        _ = stateMachine.completePageTransition(sessionToken: session.token)
    }

    private func transitionBack(session: ActiveSession) {
        guard session.pageStack.count > 1,
              let model = presentationModel else {
            return
        }
        let parentPageID = session.pageStack[session.pageStack.count - 2]
        guard let parentPage = session.frozenContent?.page(id: parentPageID),
              case .applied = stateMachine.beginPageTransition(
                  to: parentPageID,
                  sessionToken: session.token
              ) else {
            return
        }
        cancelSubmenuDwell()
        model.isTransitioning = true
        session.pageStack.removeLast()
        session.selectionEngine.reset()
        session.hasMovedOutwardOnCurrentPage = false
        model.replacePage(
            pageID: parentPage.id,
            pageName: parentPage.name,
            pageDepth: session.pageStack.count - 1,
            segments: parentPage.segments
        )
        model.isTransitioning = false
        _ = stateMachine.completePageTransition(sessionToken: session.token)
    }

    private func scheduleSubmenuDwell(
        slotIndex: Int,
        pageID: UUID,
        session: ActiveSession
    ) {
        cancelSubmenuDwell()
        let token = session.token
        let currentPageID = presentationModel?.pageID
        submenuDwellTask = timerScheduler.scheduleOnce(
            after: session.profile.interaction.submenuDwellDurationSeconds
        ) { [weak self] in
            guard let self,
                  let active = self.activeSession,
                  active.token == token,
                  self.presentationModel?.pageID == currentPageID,
                  self.presentationModel?.selectedSlotIndex == slotIndex else {
                return
            }
            self.transition(to: pageID, session: active)
        }
    }

    private func cancelSubmenuDwell() {
        submenuDwellTask?.cancel()
        submenuDwellTask = nil
    }

    private func dispatchExecution(
        _ segment: CommandWheelPresentedSegment,
        session: ActiveSession
    ) {
        guard case .command(let reference) = segment.kind else { return }
        let context = CommandInvocationContext(
            source: .commandWheel(
                profileID: session.profile.id,
                pageID: segment.pageID,
                segmentID: segment.sourceSegmentID
            ),
            frontmostApplicationBundleIdentifier: session.frontmostContext?.bundleIdentifier,
            screenIdentifier: session.position.display.identifier,
            timestamp: session.invocationDate
        )
        let token = session.token

        inputLifecycle.stop()
        cancelSubmenuDwell()
        windowPresenter.dismiss()
        _ = stateMachine.executionCompleted(sessionToken: token)
        _ = stateMachine.dismissalCompleted(sessionToken: token)
        presentationModel = nil
        activeSession = nil

        let taskID = makeUUID()
        let commandCoordinator = commandCoordinator
        let feedback = resultFeedback
        let task = Task { [weak self] in
            do {
                let result = try await commandCoordinator.execute(
                    reference: reference,
                    context: context
                )
                feedback.commandWheelDidComplete(result: result, context: context)
            } catch is CancellationError {
                // Application shutdown owns cancellation and must not present stale feedback.
            } catch {
                feedback.commandWheelDidFail(error: error, context: context)
            }
            self?.executionTasks[taskID] = nil
        }
        executionTasks[taskID] = task
    }

    private func cancelActiveSession(_ reason: CommandWheelCancellationReason) {
        guard let token = activeSession?.token else { return }
        _ = stateMachine.cancel(reason, sessionToken: token)
        completeDismissal(token: token)
    }

    private func completeDismissal(token: CommandWheelSessionToken) {
        inputLifecycle.stop()
        cancelSubmenuDwell()
        windowPresenter.dismiss()
        _ = stateMachine.dismissalCompleted(sessionToken: token)
        presentationModel = nil
        activeSession = nil
    }

    private func failAndDismiss(
        _ reason: CommandWheelFailureReason,
        token: CommandWheelSessionToken
    ) {
        _ = stateMachine.fail(reason, sessionToken: token)
        _ = stateMachine.beginFailureDismissal(sessionToken: token)
        completeDismissal(token: token)
    }

    private func displayConfigurationChanged() {
        guard activeSession != nil else { return }
        // Dock, menu-bar, scale, or arrangement changes can invalidate the captured visible frame
        // without disconnecting the display. Cancel instead of using stale geometry.
        cancelActiveSession(.displayUnavailable)
    }

    private func frontmostApplicationChanged(_ processIdentifier: Int32?) {
        guard let activeSession else { return }
        if processIdentifier == activeSession.frontmostContext?.processIdentifier { return }
        if activeSession.profile.activationBehavior == .toggle,
           processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Toggle mode intentionally activates Commandly only to receive keyboard input.
            return
        }
        cancelActiveSession(.contextLost)
    }

    private func isInsideVisibleWheel(_ location: CGPoint) -> Bool {
        guard let activeSession else { return false }
        return activeSession.selectionEngine.geometry.distance(
            from: activeSession.position.actualCenter,
            to: location
        ) <= activeSession.profile.appearance.wheelRadius
    }

    private func applicationWillTerminate() {
        tearDown()
    }

    private static func contentSize(
        for appearance: CommandWheelAppearanceConfiguration
    ) -> CGSize {
        let margin: CGFloat = 72
        let edge = CGFloat(max(80, appearance.wheelRadius)) * 2 + margin * 2
        return CGSize(width: edge, height: edge)
    }

    isolated deinit {
        submenuDwellTask?.cancel()
        for task in executionTasks.values { task.cancel() }
        inputLifecycle.stop()
        windowPresenter.tearDown()
    }
}

@MainActor
private final class ActiveSession {
    let token: CommandWheelSessionToken
    let profile: CommandWheelProfile
    let frontmostContext: FrontmostApplicationContext?
    let displayEnvironment: CommandWheelDisplayEnvironmentSnapshot
    let position: CommandWheelPosition
    let invocationDate: Date

    var frozenContent: CommandWheelFrozenContent?
    var pageStack = [UUID]()
    var selectionEngine: CommandWheelSelectionEngine
    var hasMovedOutwardOnCurrentPage = false
    var pendingReleaseLocation: CGPoint?

    init(
        token: CommandWheelSessionToken,
        profile: CommandWheelProfile,
        frontmostContext: FrontmostApplicationContext?,
        displayEnvironment: CommandWheelDisplayEnvironmentSnapshot,
        position: CommandWheelPosition,
        invocationDate: Date,
        selectionEngine: CommandWheelSelectionEngine
    ) {
        self.token = token
        self.profile = profile
        self.frontmostContext = frontmostContext
        self.displayEnvironment = displayEnvironment
        self.position = position
        self.invocationDate = invocationDate
        self.selectionEngine = selectionEngine
    }
}
