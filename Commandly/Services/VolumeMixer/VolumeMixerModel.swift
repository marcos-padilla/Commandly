import AppKit
import CoreAudio
import Foundation
import Observability
import Observation

/// Per-application volume and output routing, which macOS does not offer natively.
///
/// For every app the user turns down or routes to a specific output, a muted CoreAudio process
/// tap removes the app's sound from the original output and a private aggregate device
/// re-renders the tapped stream with the chosen gain. Apps sitting on the system default output
/// at 100% are left completely untouched — no tap is ever created on their behalf.
///
/// All published state lives on the main actor. Reading the audio HAL happens on `halQueue`,
/// because a device being reconfigured can hold a single property read for as long as the audio
/// daemon holds that device, and building a tap happens on `buildQueue`, because creating the
/// CoreAudio objects takes tens of milliseconds.
@Observable
@MainActor
final class VolumeMixerModel {
    /// Whether this system can tap process audio at all.
    nonisolated static var supportsPerApplicationVolume: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    /// Preferences. Assigning persists them and re-applies whatever they change.
    var settings: VolumeMixerSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            if settings.usesFinerVolumeSteps != oldValue.usesFinerVolumeSteps {
                onFinerVolumeStepsChange?(settings.usesFinerVolumeSteps)
            }
            if settings.switchesOutputsWithShortcut != oldValue.switchesOutputsWithShortcut {
                onOutputShortcutChange?(settings.switchesOutputsWithShortcut)
            }
            if settings.showsFinder != oldValue.showsFinder
                || settings.hidesInactiveApplications != oldValue.hidesInactiveApplications {
                publishHiddenApplications()
                refresh()
            }
        }
    }

    private(set) var applications: [MixerApplication] = []
    private(set) var outputDevices: [MixerOutputDevice] = []
    private(set) var inputDevices: [MixerInputDevice] = []
    private(set) var currentOutputDeviceUID: String?
    private(set) var currentSystemSoundOutputDeviceUID: String?
    private(set) var currentInputDeviceUID: String?
    /// `nil` when the current output exposes no software volume control.
    private(set) var systemOutputVolume: Double?
    /// `nil` when the current output has no mute switch of its own.
    private(set) var systemOutputMuted: Bool?
    /// Set when a device could not be made the default, for the panel's inline error.
    private(set) var outputSwitchError: String?
    /// Set when tap creation failed with a permission error, so the panel can point at the
    /// system audio recording consent.
    private(set) var needsAudioCapturePermission = false
    /// Apps kept off the list, so the panel can offer to bring any of them back.
    private(set) var hiddenApplications: [MixerHiddenApplication] = []

    /// Called when the finer-volume-steps preference flips, so the event tap can follow it.
    var onFinerVolumeStepsChange: ((Bool) -> Void)?
    /// Called when the output-cycling preference flips, so the shortcut can follow it.
    var onOutputShortcutChange: ((Bool) -> Void)?

    private let store: any VolumeMixerSettingsStoring
    private let logger: AppLogger

    // MARK: Engines

    private var engines: [String: any MixerGainEngine] = [:]
    /// Arbitrates builds running off the main actor: suppresses duplicates while a slider is
    /// being dragged, and discards a build that lands after the mixer moved on.
    private var builds = MixerEngineBuilds()
    /// When each row's engine last changed, so a row whose audio objects flicker is rebuilt once
    /// instead of once per notification.
    private var engineChangeAt: [String: Double] = [:]
    /// When each row's audio last went away. Kept apart from the change stamp above: the wait
    /// before letting a tap go is measured from the moment the audio disappeared.
    private var objectsLostAt: [String: Double] = [:]
    /// The last render count seen per row, so a wedged engine can be told from a healthy one.
    private var engineRenderProgress: [String: MixerRoutingRules.EngineRenderObservation] = [:]
    /// A dead audio path gets one replacement. If that exact replacement also never renders, the
    /// row stays untapped so system audio fails open.
    private var engineRecovery = MixerEngineRecovery()
    private var engineReconcilePending = false

    // MARK: Session-only state

    /// Volumes and routes of rows without a persistence id: adjustable while the process runs,
    /// never written to disk.
    private var sessionVolumes: [String: Double] = [:]
    private var sessionRoutes: [String: String] = [:]
    private var lastAudibleVolume: [String: Double] = [:]

    // MARK: Listeners

    private var isListening = false
    private var globalListenerSelectors: [AudioObjectPropertySelector] = []
    private var runningListeners = Set<AudioObjectID>()
    private var outputControlListenerDevice: AudioObjectID?
    private var outputControlListenerAddresses: [AudioObjectPropertyAddress] = []
    private var outputControlRefreshGeneration = 0
    private var wakeObserver: NSObjectProtocol?

    // MARK: Refresh

    private var refreshCoordinator = MixerRefreshCoordinator()
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    private static let listenerRefreshInterval: CFAbsoluteTime = 0.2

    /// What the headphone-disconnect protection did to the system volume, so it can be undone.
    private var loweredOutput: MixerLoweredOutputState.LoweredOutput?
    private var lastAutomaticallyLoweredOutputUID: String?

    // MARK: Output writes

    private var pendingOutputAdjustment: OutputAdjustment?
    private var outputWriteInFlight: OutputAdjustment?
    private let outputControlLock = NSLock()
    private var outputControlLifetime = UUID()

    private let halQueue = DispatchQueue(
        label: "com.businessmate360.Commandly.mixer.hal",
        qos: .userInitiated
    )
    /// Deliberately not `halQueue`: creating a tap and its aggregate takes far longer than
    /// reading a property, and the panel must never wait behind one to learn which devices exist.
    private let buildQueue = DispatchQueue(
        label: "com.businessmate360.Commandly.mixer.build",
        qos: .userInitiated
    )

    private var isStopped = false

    init(
        store: any VolumeMixerSettingsStoring = UserDefaultsVolumeMixerSettingsStore(),
        logger: AppLogger = Loggers.application
    ) {
        self.store = store
        self.logger = logger
        self.settings = store.load()
    }

    // MARK: - Lifecycle

    /// Whether the mixer has anything to do before the panel is opened.
    ///
    /// A tap is only ever created for an app the user adjusted, so with no saved volume, no
    /// saved route, and no preference that reaches outside the panel, there is nothing to hold
    /// and no reason to watch the audio system at all.
    var hasWorkAtLaunch: Bool {
        store.applicationVolumes().isEmpty == false
            || store.applicationRoutes().isEmpty == false
            || settings.lowersVolumeOnHeadphonesDisconnect
            || settings.switchesOutputsWithShortcut
    }

    /// Starts watching audio devices and processes. Saved volumes re-apply as soon as the
    /// matching app produces sound; no panel interaction is needed.
    func start() {
        isStopped = false
        publishHiddenApplications()

        guard isListening == false else {
            refresh()
            return
        }
        isListening = true
        installGlobalListener(kAudioHardwarePropertyDevices)
        installGlobalListener(kAudioHardwarePropertyDefaultOutputDevice)
        installGlobalListener(kAudioHardwarePropertyDefaultSystemOutputDevice)
        installGlobalListener(kAudioHardwarePropertyDefaultInputDevice)
        if Self.supportsPerApplicationVolume {
            installGlobalListener(kAudioHardwarePropertyProcessObjectList)
        }

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { self.handleWake() }
            }
        }
        refresh()
    }

    /// Tears every tap down so all apps return to untouched system output, and hands back the
    /// one system setting the mixer changes on its own.
    func stopEngines() {
        isStopped = true
        builds.invalidateAll()
        for engine in engines.values { engine.stop() }
        engines.removeAll()
        engineChangeAt.removeAll()
        objectsLostAt.removeAll()
        engineRenderProgress.removeAll()
        engineRecovery.clearAll()
        restoreLoweredOutputVolume()
    }

    /// Full teardown: taps, per-process listeners, and global listeners all go away, and the
    /// published state empties out.
    func tearDown() {
        stopEngines()
        sessionVolumes.removeAll()
        sessionRoutes.removeAll()
        // A refresh already reading the HAL must not publish into a mixer that stopped watching.
        refreshCoordinator.discardInFlight()
        pruneRunningListeners(keeping: [])
        removeGlobalListeners()

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        applications = []
        hiddenApplications = []
        outputDevices = []
        inputDevices = []
        currentOutputDeviceUID = nil
        currentSystemSoundOutputDeviceUID = nil
        currentInputDeviceUID = nil
        systemOutputVolume = nil
        systemOutputMuted = nil
        outputSwitchError = nil
        needsAudioCapturePermission = false
    }

    private func handleWake() {
        // A wake can wedge an engine while leaving the HAL snapshot byte-identical, and the
        // publish step skips reconciliation when nothing changed. Dropping the stored render
        // observations and reconciling directly arms the note-then-recheck sequence, so a frozen
        // engine is caught even on a quiet wake.
        engineRenderProgress.removeAll()
        engineRecovery.clearAll()
        refresh()
        reconcileEngines(with: applications)
        scheduleEngineReconcile(after: 2)
    }

    // MARK: - HAL listeners

    /// Identifies these registrations as ours. Unretained is safe: the model is owned by the app
    /// runtime for the lifetime of the process and removes every listener in `tearDown`.
    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    /// Deliberately the plain callback rather than a closure: a closure handed back for removal
    /// never matches the one registered, so the call reports success while the listener stays.
    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let model = Unmanaged<VolumeMixerModel>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { model.scheduleListenerRefresh() }
        }
        return noErr
    }

    private static let outputControlListenerCallback: AudioObjectPropertyListenerProc = {
        device, _, _, client in
        guard let client else { return noErr }
        let model = Unmanaged<VolumeMixerModel>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { model.scheduleOutputControlRefresh(for: device) }
        }
        return noErr
    }

    private func installGlobalListener(_ selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            Self.listenerCallback,
            listenerClient
        ) == noErr else { return }
        globalListenerSelectors.append(selector)
    }

    private func removeGlobalListeners() {
        guard isListening else { return }
        isListening = false
        removeOutputControlListeners()
        for selector in globalListenerSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.listenerCallback,
                listenerClient
            )
        }
        globalListenerSelectors.removeAll()
    }

    /// Volume and mute belong to the current output device, not the HAL's system object, so
    /// these listeners move whenever that device changes.
    private func subscribeToOutputControls(of device: AudioObjectID?) {
        guard outputControlListenerDevice != device else { return }
        removeOutputControlListeners()
        guard let device else { return }

        let selectors = CoreAudioProperties.outputVolumeSelectors + [kAudioDevicePropertyMute]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            if AudioObjectAddPropertyListener(
                device, &address, Self.outputControlListenerCallback, listenerClient
            ) == noErr {
                outputControlListenerAddresses.append(address)
            }
        }
        if outputControlListenerAddresses.isEmpty == false {
            outputControlListenerDevice = device
        }
    }

    private func removeOutputControlListeners() {
        if let device = outputControlListenerDevice {
            for var address in outputControlListenerAddresses {
                AudioObjectRemovePropertyListener(
                    device, &address, Self.outputControlListenerCallback, listenerClient
                )
            }
        }
        outputControlListenerDevice = nil
        outputControlListenerAddresses.removeAll()
        outputControlRefreshGeneration &+= 1
        outputControlLock.withLock { outputControlLifetime = UUID() }
        // A superseded write is reported as handled: replaying it would adjust the new output.
        let pending = pendingOutputAdjustment
        pendingOutputAdjustment = nil
        pending?.completion(true)
    }

    private func subscribeToRunningChanges(of object: AudioObjectID) {
        guard runningListeners.contains(object) == false else { return }
        var address = CoreAudioProperties.isRunningOutputAddress()
        if AudioObjectAddPropertyListener(
            object, &address, Self.listenerCallback, listenerClient
        ) == noErr {
            runningListeners.insert(object)
        }
    }

    /// Drops the listeners of process objects that no longer exist.
    ///
    /// Removal on a dead object can fail; the entry is forgotten either way. Object ids do come
    /// back — the HAL reuses them — and a returning id is simply subscribed again on the next
    /// refresh. Without removal, a week of app churn leaves thousands of dead registrations.
    private func pruneRunningListeners(keeping current: Set<AudioObjectID>) {
        for object in runningListeners where current.contains(object) == false {
            var address = CoreAudioProperties.isRunningOutputAddress()
            AudioObjectRemovePropertyListener(
                object, &address, Self.listenerCallback, listenerClient
            )
            runningListeners.remove(object)
        }
    }

    /// One hardware event fires several listeners back to back, and a busy HAL can keep that
    /// stream going for as long as the panel is open. An isolated notification still refreshes
    /// immediately — a headphone unplug must react now — while a burst folds into one trailing
    /// refresh so the panel does not redraw once per listener.
    private func scheduleListenerRefresh() {
        guard refreshPending == false else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastListenerRefreshAt
        if elapsed >= Self.listenerRefreshInterval {
            lastListenerRefreshAt = now
            refresh()
            return
        }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.listenerRefreshInterval - elapsed)) {
            MainActor.assumeIsolated {
                self.refreshPending = false
                self.lastListenerRefreshAt = CFAbsoluteTimeGetCurrent()
                self.refresh()
            }
        }
    }

    // MARK: - System output volume and mute

    /// One in-flight HAL write at a time; a burst keeps only its newest requested level. Device
    /// changes never inherit a write meant for the previous output.
    private struct OutputAdjustment {
        let device: AudioObjectID
        let lifetime: UUID
        var volume: Double?
        var muted: Bool?
        var completion: (Bool) -> Void
    }

    /// Adjusts the system output. UI feedback is immediate; the HAL write follows.
    func requestOutputAdjustment(
        volume: Double? = nil,
        muted: Bool? = nil,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        guard let device = outputControlListenerDevice,
              volume?.isFinite != false,
              volume == nil || systemOutputVolume != nil,
              muted == nil || systemOutputMuted != nil else {
            completion(false)
            return
        }

        outputControlRefreshGeneration &+= 1
        let previous = pendingOutputAdjustment
        var adjustment = previous ?? OutputAdjustment(
            device: device,
            lifetime: outputControlLock.withLock { outputControlLifetime },
            completion: completion
        )
        adjustment.completion = completion

        if let volume {
            let value = min(1, max(0, volume))
            adjustment.volume = value
            systemOutputVolume = value
            // Asking for sound means asking for sound: a level above zero also unmutes.
            if value > 0, systemOutputMuted != nil {
                adjustment.muted = false
                systemOutputMuted = false
            }
        }
        if let muted {
            adjustment.muted = muted
            systemOutputMuted = muted
        }

        pendingOutputAdjustment = adjustment
        previous?.completion(true)
        drainOutputAdjustment()
    }

    func toggleSystemOutputMute() {
        guard let muted = systemOutputMuted else { return }
        requestOutputAdjustment(muted: muted == false)
    }

    private func isCurrentOutputAdjustment(_ adjustment: OutputAdjustment) -> Bool {
        outputControlLock.withLock { outputControlLifetime == adjustment.lifetime }
    }

    private var hasCurrentOutputAdjustment: Bool {
        pendingOutputAdjustment != nil || outputWriteInFlight.map(isCurrentOutputAdjustment) == true
    }

    private func applyOutputControls(volume: Double?, muted: Bool?) {
        guard hasCurrentOutputAdjustment == false else { return }
        if systemOutputVolume != volume { systemOutputVolume = volume }
        if systemOutputMuted != muted { systemOutputMuted = muted }
    }

    private func drainOutputAdjustment() {
        guard outputWriteInFlight == nil, let adjustment = pendingOutputAdjustment else { return }
        pendingOutputAdjustment = nil
        guard isCurrentOutputAdjustment(adjustment),
              outputControlListenerDevice == adjustment.device else {
            adjustment.completion(true)
            return
        }
        outputWriteInFlight = adjustment

        halQueue.async {
            let device = adjustment.device
            var success = MainActor.assumeIsolated { self.isCurrentOutputAdjustment(adjustment) }
                && CoreAudioProperties.defaultDeviceID(
                    selector: kAudioHardwarePropertyDefaultOutputDevice
                ) == device
            if success, let volume = adjustment.volume {
                success = CoreAudioProperties.setOutputVolume(Float32(volume), for: device)
            }
            if success, let muted = adjustment.muted {
                success = CoreAudioProperties.setOutputMuted(muted, for: device)
            }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.outputWriteInFlight = nil
                    let isCurrent = self.isCurrentOutputAdjustment(adjustment)
                    adjustment.completion(isCurrent == false || success)
                    if self.pendingOutputAdjustment != nil {
                        self.drainOutputAdjustment()
                    } else if isCurrent {
                        self.scheduleOutputControlRefresh(for: device)
                    } else {
                        self.scheduleListenerRefresh()
                    }
                }
            }
        }
    }

    private func scheduleOutputControlRefresh(for device: AudioObjectID) {
        guard isListening, outputControlListenerDevice == device else { return }
        outputControlRefreshGeneration &+= 1
        let generation = outputControlRefreshGeneration

        // A drag and the volume keys emit several properties per step. Read once after the burst
        // so an older callback cannot pull the slider back while a newer value is on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            MainActor.assumeIsolated {
                guard self.isListening,
                      self.outputControlListenerDevice == device,
                      self.outputControlRefreshGeneration == generation else { return }
                self.halQueue.async {
                    let volume = CoreAudioProperties.hasSettableOutputVolume(for: device)
                        ? CoreAudioProperties.outputVolume(for: device).map(Double.init)
                        : nil
                    let muted = CoreAudioProperties.outputMuted(for: device)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard self.isListening,
                                  self.outputControlListenerDevice == device,
                                  self.outputControlRefreshGeneration == generation else { return }
                            self.applyOutputControls(volume: volume, muted: muted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Device selection

    /// Makes a device the system output for everything, and clears the per-app routes: the user
    /// just chose this output for the whole Mac.
    @discardableResult
    func setSystemOutputDeviceUID(_ uid: String) -> Bool {
        guard let sanitized = MixerRoutingRules.sanitizedDeviceUID(uid),
              let device = outputDevices.first(where: {
                  $0.uid == sanitized && $0.canBeDefaultOutput
              }) else {
            outputSwitchError = "That output is no longer available."
            refresh()
            return false
        }

        let status = CoreAudioProperties.setDefaultDevice(
            device.objectID,
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
        guard status == noErr else {
            outputSwitchError = "The output could not be changed (OSStatus \(status))."
            refresh()
            return false
        }

        outputSwitchError = nil
        // The default output just changed by this app's own hand, so a refresh still reading the
        // previous devices is thrown away; the one at the end of this method replaces it.
        refreshCoordinator.discardInFlight()

        let routes = MixerRoutingRules.routesAfterSystemOutputSwitch(
            routes: store.applicationRoutes(),
            switchSucceeded: true
        )
        store.saveApplicationRoutes(routes)

        currentOutputDeviceUID = device.uid
        outputDevices = outputDevices.map { current in
            MixerOutputDevice(
                id: current.id,
                uid: current.uid,
                name: current.name,
                isDefault: current.uid == device.uid,
                isHeadphones: current.isHeadphones,
                canBeDefaultOutput: current.canBeDefaultOutput,
                canBeDefaultSystemOutput: current.canBeDefaultSystemOutput,
                objectID: current.objectID
            )
        }

        // Builds started for the previous device can no longer be installed; the engines
        // themselves stay live until reconciliation has their replacement running.
        builds.invalidateAll()

        let availableUIDs = Set(outputDevices.map(\.uid))
        let volumes = store.applicationVolumes()
        applications = applications.map { current in
            var application = current
            application.volume = storedVolume(for: application.identity, saved: volumes)
                ?? application.volume
            applyOutputRoute(
                to: &application,
                savedRoutes: routes,
                availableUIDs: availableUIDs,
                defaultUID: device.uid
            )
            return application
        }

        reconcileEngines(with: applications)
        clearPermissionFlagIfIdle()
        refresh()
        return true
    }

    @discardableResult
    func setSystemSoundOutputDeviceUID(_ uid: String) -> Bool {
        guard let sanitized = MixerRoutingRules.sanitizedDeviceUID(uid),
              let device = outputDevices.first(where: {
                  $0.uid == sanitized && $0.canBeDefaultSystemOutput
              }) else {
            outputSwitchError = "That output is no longer available."
            refresh()
            return false
        }

        let status = CoreAudioProperties.setDefaultDevice(
            device.objectID,
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice
        )
        guard status == noErr else {
            outputSwitchError = "The alert output could not be changed (OSStatus \(status))."
            refresh()
            return false
        }

        outputSwitchError = nil
        refreshCoordinator.discardInFlight()
        currentSystemSoundOutputDeviceUID = device.uid
        refresh()
        return true
    }

    @discardableResult
    func setInputDeviceUID(_ uid: String) -> Bool {
        guard let sanitized = MixerRoutingRules.sanitizedDeviceUID(uid),
              let device = inputDevices.first(where: { $0.uid == sanitized }) else {
            outputSwitchError = "That microphone is no longer available."
            refresh()
            return false
        }

        let status = CoreAudioProperties.setDefaultDevice(
            device.objectID,
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        guard status == noErr else {
            outputSwitchError = "The microphone could not be changed (OSStatus \(status))."
            refresh()
            return false
        }

        outputSwitchError = nil
        refreshCoordinator.discardInFlight()
        currentInputDeviceUID = device.uid
        refresh()
        return true
    }

    /// Moves the system output to the next device in the user's chosen cycle.
    @discardableResult
    func switchToNextOutput() -> Bool {
        let availableUIDs = Set(outputDevices.filter(\.canBeDefaultOutput).map(\.uid))
        guard let nextUID = MixerRoutingRules.nextSelectedOutputDeviceUID(
            currentUID: currentOutputDeviceUID,
            selectedUIDs: settings.switcherDeviceUIDs,
            availableUIDs: availableUIDs
        ) else { return false }
        return setSystemOutputDeviceUID(nextUID)
    }

    // MARK: - Per-application volume and routing

    func setVolume(_ volume: Double, for application: MixerApplication) {
        guard application.isBypassed == false else { return }
        engineRecovery.clear(application.id)
        let clamped = MixerRoutingRules.sanitizedApplicationVolume(volume)
        persistVolume(clamped, for: application)
        if clamped > 0.001 { lastAudibleVolume[application.id] = clamped }

        guard let index = applications.firstIndex(where: { $0.id == application.id }) else {
            applyRouting(for: application)
            return
        }
        applications[index].volume = clamped
        applyRouting(for: applications[index])
    }

    func toggleMute(_ application: MixerApplication) {
        if application.volume > 0.001 {
            lastAudibleVolume[application.id] = application.volume
            setVolume(0, for: application)
        } else {
            setVolume(lastAudibleVolume[application.id] ?? 1, for: application)
        }
    }

    func setOutputDeviceUID(_ uid: String?, for application: MixerApplication) {
        guard application.isBypassed == false else { return }
        engineRecovery.clear(application.id)
        let sanitized = MixerRoutingRules.sanitizedDeviceUID(uid)
        persistRoute(sanitized, for: application)

        guard let index = applications.firstIndex(where: { $0.id == application.id }) else { return }
        var routes = store.applicationRoutes()
        if let persistenceID = application.persistenceID {
            if let sanitized {
                routes[persistenceID] = sanitized
            } else {
                routes.removeValue(forKey: persistenceID)
            }
        }
        applyOutputRoute(
            to: &applications[index],
            savedRoutes: routes,
            availableUIDs: Set(outputDevices.map(\.uid)),
            defaultUID: currentOutputDeviceUID
        )
        // The running tap is left alone here: `applyRouting` builds the one for the new device
        // first and stops this one only after it is running, so the sound never falls back to
        // the old output in between.
        applyRouting(for: applications[index])
    }

    // MARK: - List visibility

    /// Takes a row off the list. Its saved volume and route are kept for the day it comes back;
    /// while hidden the app is never tapped, so it always plays untouched.
    func hideFromList(_ application: MixerApplication) {
        guard let persistenceID = application.persistenceID else { return }
        if persistenceID == MixerRoutingRules.finderBundleIdentifier {
            settings.showsFinder = false
            return
        }
        var hidden = store.hiddenApplications()
        hidden[persistenceID] = application.name
        store.saveHiddenApplications(hidden)
        publishHiddenApplications()
        refresh()
    }

    /// Puts a hidden app back on the list; its saved volume and route apply again on the next
    /// refresh.
    func showInList(id: String) {
        if id == MixerRoutingRules.finderBundleIdentifier {
            settings.showsFinder = true
            return
        }
        var hidden = store.hiddenApplications()
        hidden.removeValue(forKey: id)
        store.saveHiddenApplications(hidden)
        publishHiddenApplications()
        refresh()
    }

    private func publishHiddenApplications() {
        var entries = store.hiddenApplications().map {
            MixerHiddenApplication(id: $0.key, name: $0.value)
        }
        if settings.showsFinder == false {
            let finderID = MixerRoutingRules.finderBundleIdentifier
            let name = NSRunningApplication
                .runningApplications(withBundleIdentifier: finderID)
                .first?.localizedName ?? "Finder"
            entries.append(MixerHiddenApplication(id: finderID, name: name))
        }
        entries.sort {
            MixerRoutingRules.displayOrderedBefore(
                name: $0.name, id: $0.id, otherName: $1.name, otherID: $1.id
            )
        }
        if hiddenApplications != entries { hiddenApplications = entries }
    }

    /// The rows the panel shows, after the "hide inactive apps" preference.
    var visibleApplications: [MixerApplication] {
        applications.filter {
            MixerRoutingRules.shouldShowApplication(
                isPlaying: $0.isPlaying,
                volume: $0.volume,
                selectedOutputDeviceUID: $0.selectedOutputDeviceUID,
                hidesInactiveApplications: settings.hidesInactiveApplications
            )
        }
    }

    // MARK: - Refresh

    /// Kicks off one refresh. Reading the HAL happens on `halQueue`; everything published, every
    /// engine, and every listener record is touched back on the main actor, where it lives.
    private func refresh() {
        // A throttled refresh can land after teardown; watching is over.
        guard isListening else { return }
        // A pass already reading the HAL holds the slot: a second one now would read against
        // state the first has not published yet. The request is remembered and runs after it.
        guard let generation = refreshCoordinator.begin() else { return }

        let request = MixerRefreshRequest(
            previousDefaultOutputUID: currentOutputDeviceUID,
            previousOutputDevices: outputDevices,
            lowered: MixerLoweredOutputState(
                lastAutomaticallyLoweredOutputUID: lastAutomaticallyLoweredOutputUID,
                loweredOutput: loweredOutput
            ),
            lowersVolumeOnHeadphonesDisconnect: settings.lowersVolumeOnHeadphonesDisconnect,
            lowerToPercent: settings.headphonesDisconnectVolumePercent,
            savedVolumes: store.applicationVolumes(),
            savedRoutes: store.applicationRoutes(),
            sessionVolumes: sessionVolumes,
            sessionRoutes: sessionRoutes,
            showsFinder: settings.showsFinder,
            hiddenRowIDs: MixerRoutingRules.hiddenRowIDs(
                hiddenApplications: store.hiddenApplications(),
                showsFinder: settings.showsFinder
            ),
            ownProcessID: ProcessInfo.processInfo.processIdentifier
        )

        halQueue.async {
            let snapshot = MixerSnapshotReader.read(request)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(snapshot, generation: generation) }
            }
        }
    }

    /// Turns one HAL snapshot into published state, engines, and listener records.
    private func apply(_ snapshot: MixerRefreshSnapshot, generation: Int) {
        // The mixer no longer wants this pass: it stopped, or changed the output itself, while
        // the pass was reading. The one thing still worth keeping is a volume the pass lowered
        // on the HAL, so the speakers can be handed back later.
        guard refreshCoordinator.finish(generation) else {
            if snapshot.lowered.loweredOutput != nil {
                lastAutomaticallyLoweredOutputUID = snapshot.lowered.lastAutomaticallyLoweredOutputUID
                loweredOutput = snapshot.lowered.loweredOutput
            }
            return
        }
        let refreshAgain = refreshCoordinator.takeRepeatRequest()
        guard isListening else { return }
        defer { if refreshAgain { refresh() } }

        lastAutomaticallyLoweredOutputUID = snapshot.lowered.lastAutomaticallyLoweredOutputUID
        loweredOutput = snapshot.lowered.loweredOutput

        if outputSwitchError != nil,
           snapshot.defaultOutputUID != currentOutputDeviceUID
            || snapshot.systemSoundOutputUID != currentSystemSoundOutputDeviceUID
            || snapshot.defaultInputUID != currentInputDeviceUID {
            outputSwitchError = nil
        }

        let audioEnvironmentChanged = currentOutputDeviceUID != nil
            && (snapshot.defaultOutputUID != currentOutputDeviceUID
                || snapshot.outputDevices != outputDevices)
        if audioEnvironmentChanged {
            // Builds aimed at the previous audio environment can no longer be installed;
            // reconciliation replaces the live engines one by one, each new tap running before
            // its predecessor stops.
            builds.invalidateAll()
        }

        // Observation notifies on every assignment, and refreshes run on every HAL
        // notification — publish only real changes or a chatty HAL redraws the panel
        // continuously.
        if currentOutputDeviceUID != snapshot.defaultOutputUID {
            currentOutputDeviceUID = snapshot.defaultOutputUID
        }
        if currentSystemSoundOutputDeviceUID != snapshot.systemSoundOutputUID {
            currentSystemSoundOutputDeviceUID = snapshot.systemSoundOutputUID
        }
        if currentInputDeviceUID != snapshot.defaultInputUID {
            currentInputDeviceUID = snapshot.defaultInputUID
        }
        if outputDevices != snapshot.outputDevices { outputDevices = snapshot.outputDevices }
        if inputDevices != snapshot.inputDevices { inputDevices = snapshot.inputDevices }

        subscribeToOutputControls(of: snapshot.defaultOutputDeviceID)
        applyOutputControls(volume: snapshot.systemOutputVolume, muted: snapshot.systemOutputMuted)

        guard let next = snapshot.applications else {
            if applications.isEmpty == false { applications = [] }
            return
        }

        pruneRunningListeners(keeping: Set(snapshot.processObjects))
        for object in snapshot.processObjects {
            // Audio starting and stopping inside a process flips IsRunningOutput without
            // changing the object list, so each object is subscribed to individually.
            subscribeToRunningChanges(of: object)
        }

        guard audioEnvironmentChanged || next != applications else { return }
        if applications != next { applications = next }
        reconcileEngines(with: next)
        clearPermissionFlagIfIdle()
    }

    // MARK: - Engines

    /// Builds, retargets, or discards the engine for one row.
    ///
    /// A tap mutes the app on its real output and replays it through the aggregate, so an engine
    /// that goes away for even a moment hands the app straight back to the speakers at full
    /// volume. Replacements are therefore built first, and the old engine is stopped only once
    /// the new one is running.
    private func applyRouting(for application: MixerApplication) {
        guard isStopped == false else { return }
        guard application.isBypassed == false else {
            discardEngine(for: application.id)
            return
        }
        guard let targetOutputDeviceUID = application.effectiveOutputDeviceUID,
              requiresEngine(application) else {
            // System default at 100% stays true passthrough.
            discardEngine(for: application.id)
            clearPermissionFlagIfIdle()
            return
        }

        if let engine = engines[application.id],
           engine.tappedObjects == application.audioObjects,
           engine.outputDeviceUID == targetOutputDeviceUID {
            engine.gain = Float(application.volume)
            return
        }

        // Nothing is ever tapped on behalf of an app the user never adjusted.
        guard mayBeTapped(application) else {
            discardEngine(for: application.id)
            clearPermissionFlagIfIdle()
            return
        }

        let configuration = MixerEngineRecovery.Configuration(
            objects: application.audioObjects,
            outputDeviceUID: targetOutputDeviceUID
        )
        guard engineRecovery.allowsBuild(application.id, configuration: configuration) else { return }
        guard #available(macOS 14.4, *), let token = builds.begin(application.id) else { return }

        let objects = application.audioObjects
        let gain = Float(application.volume)
        let rowID = application.id
        buildQueue.async {
            let engine = TapGainEngine(
                objects: objects,
                gain: gain,
                outputDeviceUID: targetOutputDeviceUID
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.install(engine, for: rowID, token: token) }
            }
        }
    }

    /// Lands one finished build.
    private func install(_ engine: (any MixerGainEngine)?, for id: String, token: Int) {
        let isCurrentBuild = builds.isCurrent(id, token: token)
        builds.finish(id, token: token)

        // A build that started before the mixer moved on — the output device changed, a newer
        // build for the same row — would add a second live tap and render the app twice.
        guard isCurrentBuild, isStopped == false else {
            engine?.stop()
            return
        }

        guard let engine else {
            // The tap could not be created. Keeping the engine already running beats leaving the
            // app with none, unless it renders to a device that is gone, in which case it can
            // only mute the app.
            if let running = engines[id],
               outputDevices.contains(where: { $0.uid == running.outputDeviceUID }) == false {
                discardEngine(for: id)
            }
            // A row that still has a tap running is plainly not being refused for lack of
            // consent, so the permission hint stays out of it.
            if engines[id] == nil, needsAudioCapturePermission == false {
                needsAudioCapturePermission = true
                logger.info("Volume mixer could not create a process tap")
            }
            return
        }

        if needsAudioCapturePermission { needsAudioCapturePermission = false }

        // The slider may have moved, or the app's audio objects may have changed, while the
        // engine was being built. Honor the latest state, never an old tap target.
        guard let latest = applications.first(where: { $0.id == id }) else {
            engine.stop()
            return
        }
        guard latest.audioObjects == engine.tappedObjects,
              latest.effectiveOutputDeviceUID == engine.outputDeviceUID,
              requiresEngine(latest) else {
            engine.stop()
            applyRouting(for: latest)
            return
        }

        engine.gain = Float(latest.volume)
        let previous = engines.updateValue(engine, forKey: id)
        engineChangeAt[id] = CFAbsoluteTimeGetCurrent()
        // The fresh engine starts its render count over.
        engineRenderProgress.removeValue(forKey: id)
        previous?.stop()
        // A tap mutes immediately, so the render check is armed here rather than waiting for
        // another HAL event: a dead first aggregate would otherwise leave the app silent.
        reconcileEngines(with: applications)
    }

    /// Stops and forgets a row's engine. Used where silence is the intent — back to 100% on the
    /// default output, or the row is gone — never for a rebuild.
    private func discardEngine(for id: String) {
        engines.removeValue(forKey: id)?.stop()
        engineChangeAt.removeValue(forKey: id)
        objectsLostAt.removeValue(forKey: id)
        engineRenderProgress.removeValue(forKey: id)
        engineRecovery.clear(id)
    }

    /// Brings the running engines in line with the current list: drops taps for rows that went
    /// away, retargets taps whose process set changed, and builds taps for newcomers.
    private func reconcileEngines(with applications: [MixerApplication]) {
        let applications = MixerSnapshotReader.coalescingDuplicateIDs(applications)
        var byID: [String: MixerApplication] = [:]
        for application in applications { byID[application.id] = application }

        let now = CFAbsoluteTimeGetCurrent()
        var nextPassDelay: Double?

        for (id, engine) in Array(engines) {
            let application = byID[id]
            let hasAudioObjects = (application?.audioObjects.isEmpty ?? true) == false

            // The row is gone, or momentarily has no audio object: an app that recreates its
            // audio unit between clips does exactly this and is back milliseconds later. Nothing
            // is audible in between, so the tap is kept for a short window instead of being
            // destroyed and rebuilt once per notification.
            guard hasAudioObjects, let application else {
                let lostAt = objectsLostAt[id]
                if let delay = MixerRoutingRules.engineTeardownDelay(
                    hasAudioObjects: false,
                    lastChangeAt: lostAt,
                    now: now
                ) {
                    if lostAt == nil { objectsLostAt[id] = now }
                    nextPassDelay = min(nextPassDelay ?? delay, delay)
                } else {
                    discardEngine(for: id)
                }
                continue
            }
            // The audio came back inside the window, so the next disappearance starts its own
            // wait rather than inheriting this one.
            objectsLostAt.removeValue(forKey: id)

            switch MixerRoutingRules.engineRenderVerdict(
                previous: engineRenderProgress[id],
                cycles: engine.renderCycles,
                isPlaying: application.isPlaying,
                now: now
            ) {
            case .note(let observation, let recheckAfter):
                engineRenderProgress[id] = observation
                if recheckAfter == nil {
                    engineRecovery.clear(id)
                } else if let recheckAfter {
                    nextPassDelay = min(nextPassDelay ?? recheckAfter, recheckAfter)
                }
            case .stalled(let recheckAfter):
                nextPassDelay = min(nextPassDelay ?? recheckAfter, recheckAfter)
            case .wedged:
                // Waking from sleep can leave an aggregate whose IO proc never runs again while
                // its tap keeps muting the app. The engine goes away at once, which unmutes the
                // app even if the rebuild below cannot land yet.
                engines.removeValue(forKey: id)?.stop()
                engineRenderProgress.removeValue(forKey: id)
                engineChangeAt[id] = now
                let configuration = MixerEngineRecovery.Configuration(
                    objects: engine.tappedObjects,
                    outputDeviceUID: engine.outputDeviceUID
                )
                if engineRecovery.recordFailure(id, configuration: configuration) {
                    applyRouting(for: application)
                }
                continue
            case nil:
                engineRenderProgress.removeValue(forKey: id)
            }

            guard engine.tappedObjects != application.audioObjects
                || engine.outputDeviceUID != application.effectiveOutputDeviceUID
                || requiresEngine(application) == false else { continue }

            engineChangeAt[id] = now
            guard requiresEngine(application) else {
                // Back to 100% on the default output: passthrough is the point.
                discardEngine(for: id)
                continue
            }
            // An engine rendering to a device that is gone can only mute the app, so it goes
            // right away; every other rebuild keeps its tap until the replacement is running.
            if outputDevices.contains(where: { $0.uid == engine.outputDeviceUID }) == false {
                engines.removeValue(forKey: id)?.stop()
                engineRenderProgress.removeValue(forKey: id)
            }
            applyRouting(for: application)
        }

        for application in applications
        where requiresEngine(application) && engines[application.id] == nil {
            applyRouting(for: application)
        }
        forgetEngineStateOfMissingRows(byID)

        if let nextPassDelay { scheduleEngineReconcile(after: nextPassDelay) }
    }

    /// One trailing pass for rows whose rebuild was coalesced. A single scheduled block, never a
    /// repeating timer: with nothing left to reconcile the mixer goes back to being purely
    /// event driven.
    private func scheduleEngineReconcile(after delay: Double) {
        guard engineReconcilePending == false else { return }
        engineReconcilePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.01)) {
            MainActor.assumeIsolated {
                self.engineReconcilePending = false
                guard self.isStopped == false, self.isListening else { return }
                self.reconcileEngines(with: self.applications)
            }
        }
    }

    /// Engine bookkeeping for rows that are gone.
    ///
    /// Session volumes of rows without a persistence id are deliberately kept: an app that
    /// recreates its audio unit drops off the list for a moment, and its slider must survive it.
    private func forgetEngineStateOfMissingRows(_ byID: [String: MixerApplication]) {
        for id in engineChangeAt.keys where byID[id] == nil && engines[id] == nil {
            engineChangeAt.removeValue(forKey: id)
            objectsLostAt.removeValue(forKey: id)
            engineRecovery.clear(id)
        }
    }

    private func requiresEngine(_ application: MixerApplication) -> Bool {
        MixerRoutingRules.requiresEngine(
            hasAudioObjects: application.audioObjects.isEmpty == false,
            volume: application.volume,
            selectedOutputDeviceUID: application.selectedOutputDeviceUID,
            targetOutputDeviceUID: application.effectiveOutputDeviceUID,
            defaultOutputDeviceUID: currentOutputDeviceUID
        )
    }

    private func mayBeTapped(_ application: MixerApplication) -> Bool {
        MixerRoutingRules.rowMayBeTapped(
            savedVolume: storedVolume(for: application.identity, saved: store.applicationVolumes()),
            savedRouteUID: storedRoute(for: application.identity, saved: store.applicationRoutes()),
            defaultOutputDeviceUID: currentOutputDeviceUID
        )
    }

    private func clearPermissionFlagIfIdle() {
        guard needsAudioCapturePermission,
              applications.contains(where: requiresEngine) == false,
              engines.isEmpty,
              builds.isEmpty else { return }
        needsAudioCapturePermission = false
    }

    // MARK: - Routing helpers

    private func applyOutputRoute(
        to application: inout MixerApplication,
        savedRoutes: [String: String],
        availableUIDs: Set<String>,
        defaultUID: String?
    ) {
        let selectedUID = storedRoute(for: application.identity, saved: savedRoutes)
        application.selectedOutputDeviceUID = selectedUID
        application.effectiveOutputDeviceUID = MixerRoutingRules.effectiveDeviceUID(
            selectedUID: selectedUID,
            availableUIDs: availableUIDs,
            defaultUID: defaultUID
        )
        application.outputDeviceUnavailable = MixerRoutingRules.selectedDeviceUnavailable(
            selectedUID: selectedUID,
            availableUIDs: availableUIDs
        )
    }

    private func storedVolume(for identity: MixerRowIdentity, saved: [String: Double]) -> Double? {
        MixerSnapshotReader.storedVolume(for: identity, saved: saved, session: sessionVolumes)
    }

    private func storedRoute(for identity: MixerRowIdentity, saved: [String: String]) -> String? {
        MixerSnapshotReader.storedRoute(for: identity, saved: saved, session: sessionRoutes)
    }

    private func persistVolume(_ volume: Double, for application: MixerApplication) {
        guard let persistenceID = application.persistenceID else {
            // Neither a bundle identifier nor a display name: nothing stable to write down. The
            // slider still works while the app runs.
            if MixerRoutingRules.isUnity(volume) {
                sessionVolumes.removeValue(forKey: application.id)
            } else {
                sessionVolumes[application.id] = volume
            }
            return
        }
        var volumes = store.applicationVolumes()
        if MixerRoutingRules.isUnity(volume) {
            volumes.removeValue(forKey: persistenceID)
        } else {
            volumes[persistenceID] = volume
        }
        store.saveApplicationVolumes(volumes)
    }

    private func persistRoute(_ uid: String?, for application: MixerApplication) {
        guard let persistenceID = application.persistenceID else {
            if let uid {
                sessionRoutes[application.id] = uid
            } else {
                sessionRoutes.removeValue(forKey: application.id)
            }
            return
        }
        var routes = store.applicationRoutes()
        if let uid {
            routes[persistenceID] = uid
        } else {
            routes.removeValue(forKey: persistenceID)
        }
        store.saveApplicationRoutes(routes)
    }

    /// Teardown path, deliberately synchronous: this runs while the app is quitting, so anything
    /// the mixer still owes the system has to be handed back before the process goes away.
    private func restoreLoweredOutputVolume() {
        loweredOutput = MixerSnapshotReader.restoringLoweredVolume(loweredOutput, in: outputDevices)
    }
}
