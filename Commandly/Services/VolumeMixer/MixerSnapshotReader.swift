import AppKit
import CoreAudio
import Foundation

/// Everything the main actor hands one refresh pass, copied in so the HAL pass never reads a
/// property another task can be writing.
nonisolated struct MixerRefreshRequest: Sendable {
    let previousDefaultOutputUID: String?
    let previousOutputDevices: [MixerOutputDevice]
    let lowered: MixerLoweredOutputState
    let lowersVolumeOnHeadphonesDisconnect: Bool
    let lowerToPercent: Int
    let savedVolumes: [String: Double]
    let savedRoutes: [String: String]
    let sessionVolumes: [String: Double]
    let sessionRoutes: [String: String]
    let showsFinder: Bool
    /// Persistence ids the list must leave out: the apps the user hid, plus the Finder while its
    /// own preference keeps it away.
    let hiddenRowIDs: Set<String>
    let ownProcessID: pid_t
}

/// Everything one refresh read from the HAL, handed back for the main actor to publish.
nonisolated struct MixerRefreshSnapshot: Sendable {
    let defaultOutputUID: String?
    let systemSoundOutputUID: String?
    let defaultInputUID: String?
    let outputDevices: [MixerOutputDevice]
    let inputDevices: [MixerInputDevice]
    let defaultOutputDeviceID: AudioObjectID?
    let systemOutputVolume: Double?
    let systemOutputMuted: Bool?
    /// `nil` where process taps do not exist: the app list stays empty and no process object is
    /// looked at.
    let applications: [MixerApplication]?
    let processObjects: [AudioObjectID]
    let lowered: MixerLoweredOutputState
}

/// What the headphone-disconnect protection has done to the system volume, so it can be undone.
nonisolated struct MixerLoweredOutputState: Sendable {
    struct LoweredOutput: Sendable, Equatable {
        let uid: String
        let previousVolume: Float32
        let appliedVolume: Float32
    }

    var lastAutomaticallyLoweredOutputUID: String?
    var loweredOutput: LoweredOutput?

    static let none = MixerLoweredOutputState(
        lastAutomaticallyLoweredOutputUID: nil,
        loweredOutput: nil
    )
}

/// Reads one complete picture of the audio system.
///
/// Every call here runs off the main actor: a device being reconfigured can hold a single
/// property read for as long as the audio daemon holds it, and a reconfiguration is exactly what
/// fires the listeners in the first place.
nonisolated enum MixerSnapshotReader {
    static func read(_ request: MixerRefreshRequest) -> MixerRefreshSnapshot {
        let defaultOutputUID = CoreAudioProperties.defaultDeviceUID(
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
        let systemSoundOutputUID = CoreAudioProperties.defaultDeviceUID(
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice
        )
        let defaultInputUID = CoreAudioProperties.defaultDeviceUID(
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        let outputDevices = CoreAudioProperties.outputDevices(defaultUID: defaultOutputUID)
        let inputDevices = CoreAudioProperties.inputDevices(defaultUID: defaultInputUID)
        let defaultDevice = outputDevices.first { $0.uid == defaultOutputUID }

        let lowered = loweringVolumeIfHeadphonesDisconnected(
            state: request.lowered,
            previousDefaultUID: request.previousDefaultOutputUID,
            previousOutputDevices: request.previousOutputDevices,
            nextDefaultUID: defaultOutputUID,
            nextOutputDevices: outputDevices,
            lowersOnDisconnect: request.lowersVolumeOnHeadphonesDisconnect,
            lowerToPercent: request.lowerToPercent
        )

        let systemOutputVolume = defaultDevice.flatMap { device in
            CoreAudioProperties.hasSettableOutputVolume(for: device.objectID)
                ? CoreAudioProperties.outputVolume(for: device.objectID).map(Double.init)
                : nil
        }
        let systemOutputMuted = defaultDevice.flatMap {
            CoreAudioProperties.outputMuted(for: $0.objectID)
        }

        guard VolumeMixerModel.supportsPerApplicationVolume else {
            return MixerRefreshSnapshot(
                defaultOutputUID: defaultOutputUID,
                systemSoundOutputUID: systemSoundOutputUID,
                defaultInputUID: defaultInputUID,
                outputDevices: outputDevices,
                inputDevices: inputDevices,
                defaultOutputDeviceID: defaultDevice?.objectID,
                systemOutputVolume: systemOutputVolume,
                systemOutputMuted: systemOutputMuted,
                applications: nil,
                processObjects: [],
                lowered: lowered
            )
        }

        let processObjects = CoreAudioProperties.audioProcessObjects()
        let applications = readApplications(
            request,
            processObjects: processObjects,
            availableUIDs: Set(outputDevices.map(\.uid)),
            defaultOutputUID: defaultOutputUID
        )

        return MixerRefreshSnapshot(
            defaultOutputUID: defaultOutputUID,
            systemSoundOutputUID: systemSoundOutputUID,
            defaultInputUID: defaultInputUID,
            outputDevices: outputDevices,
            inputDevices: inputDevices,
            defaultOutputDeviceID: defaultDevice?.objectID,
            systemOutputVolume: systemOutputVolume,
            systemOutputMuted: systemOutputMuted,
            applications: applications,
            processObjects: processObjects,
            lowered: lowered
        )
    }

    // MARK: - Application rows

    private static func readApplications(
        _ request: MixerRefreshRequest,
        processObjects: [AudioObjectID],
        availableUIDs: Set<String>,
        defaultOutputUID: String?
    ) -> [MixerApplication] {
        var groups: [pid_t: [AudioObjectID]] = [:]
        var playing: Set<pid_t> = []
        var bypassed: Set<pid_t> = []
        var bundleHints: [pid_t: String] = [:]

        for object in processObjects {
            var processID: pid_t = -1
            guard CoreAudioProperties.read(object, kAudioProcessPropertyPID, &processID),
                  processID > 0,
                  processID != request.ownProcessID else { continue }

            // Every regular app holding an audio connection is listed, not only the ones making
            // sound this instant, so a row is adjustable before it plays and stays put between
            // sounds.
            guard let application = ResponsibleApplication.regularApplicationOwner(of: processID)
            else { continue }
            let owner = application.processIdentifier
            let name = ResponsibleApplication.displayName(
                processID: owner,
                fallback: "pid \(owner)"
            )

            if MixerRoutingRules.bypassesProcessTap(
                bundleIdentifier: application.bundleIdentifier,
                name: name
            ) {
                bypassed.insert(owner)
            }

            var isRunningOutput: UInt32 = 0
            _ = CoreAudioProperties.read(
                object, kAudioProcessPropertyIsRunningOutput, &isRunningOutput
            )
            if isRunningOutput != 0 { playing.insert(owner) }

            groups[owner, default: []].append(object)
            if bundleHints[owner] == nil {
                // The audio object knows the bundle identifier of its own process, which is the
                // app itself whenever it plays its own sound. For a helper playing on an app's
                // behalf, the owner found above is the app and its identifier is the one that
                // counts.
                bundleHints[owner] = application.bundleIdentifier
                    ?? (processID == owner
                        ? CoreAudioProperties.processBundleIdentifier(of: object)
                        : nil)
            }
        }

        var rows: [MixerApplication] = []
        for (owner, objects) in groups {
            let fallbackName = "pid \(owner)"
            let name = ResponsibleApplication.displayName(processID: owner, fallback: fallbackName)
            // The pid fallback is not a name to save under: process identifiers recycle.
            let identity = MixerRoutingRules.rowIdentity(
                bundleIdentifier: bundleHints[owner],
                ownerProcessID: owner,
                displayName: name == fallbackName ? nil : name
            )
            // Hidden means no row, and with no row the engine reconciliation tears its tap down
            // too: an app taken off the list always plays untouched, never silently attenuated.
            guard MixerRoutingRules.isHidden(
                persistenceID: identity.persistenceID,
                hiddenIDs: request.hiddenRowIDs
            ) == false else { continue }

            let isBypassed = bypassed.contains(owner)
            let route = isBypassed
                ? nil
                : storedRoute(for: identity, saved: request.savedRoutes, session: request.sessionRoutes)

            rows.append(
                MixerApplication(
                    id: identity.rowID,
                    persistenceID: identity.persistenceID,
                    ownerProcessID: owner,
                    name: name,
                    audioObjects: objects.sorted(),
                    isPlaying: playing.contains(owner),
                    isBypassed: isBypassed,
                    selectedOutputDeviceUID: route,
                    effectiveOutputDeviceUID: isBypassed ? nil : MixerRoutingRules.effectiveDeviceUID(
                        selectedUID: route,
                        availableUIDs: availableUIDs,
                        defaultUID: defaultOutputUID
                    ),
                    outputDeviceUnavailable: isBypassed ? false : MixerRoutingRules.selectedDeviceUnavailable(
                        selectedUID: route,
                        availableUIDs: availableUIDs
                    ),
                    volume: isBypassed ? 1 : (storedVolume(
                        for: identity,
                        saved: request.savedVolumes,
                        session: request.sessionVolumes
                    ) ?? 1)
                )
            )
        }

        // The Finder plays alert sounds without holding a lasting audio connection, so it gets a
        // standing row while its preference asks for one.
        if MixerRoutingRules.needsPersistentFinderRow(
            showsFinder: request.showsFinder,
            hasFinderRow: rows.contains { $0.id == MixerRoutingRules.finderBundleIdentifier }
        ), let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: MixerRoutingRules.finderBundleIdentifier
        ).first {
            let id = MixerRoutingRules.finderBundleIdentifier
            let route = request.savedRoutes[id]
            rows.append(
                MixerApplication(
                    id: id,
                    persistenceID: id,
                    ownerProcessID: finder.processIdentifier,
                    name: finder.localizedName ?? "Finder",
                    audioObjects: [],
                    isPlaying: false,
                    selectedOutputDeviceUID: route,
                    effectiveOutputDeviceUID: MixerRoutingRules.effectiveDeviceUID(
                        selectedUID: route,
                        availableUIDs: availableUIDs,
                        defaultUID: defaultOutputUID
                    ),
                    outputDeviceUnavailable: MixerRoutingRules.selectedDeviceUnavailable(
                        selectedUID: route,
                        availableUIDs: availableUIDs
                    ),
                    volume: request.savedVolumes[id] ?? 1
                )
            )
        }

        rows.sort {
            MixerRoutingRules.displayOrderedBefore(
                name: $0.name, id: $0.id, otherName: $1.name, otherID: $1.id
            )
        }
        return coalescingDuplicateIDs(rows)
    }

    /// Two processes can resolve to the same row identity. Their audio objects belong to one
    /// engine, so the rows are merged rather than fighting over it.
    static func coalescingDuplicateIDs(_ applications: [MixerApplication]) -> [MixerApplication] {
        var merged: [MixerApplication] = []
        var indexesByID: [String: Int] = [:]

        for application in applications {
            guard let index = indexesByID[application.id] else {
                indexesByID[application.id] = merged.count
                merged.append(application)
                continue
            }

            let existing = merged[index]
            merged[index] = MixerApplication(
                id: existing.id,
                persistenceID: existing.persistenceID,
                ownerProcessID: existing.ownerProcessID,
                name: existing.name,
                audioObjects: Array(Set(existing.audioObjects).union(application.audioObjects)).sorted(),
                isPlaying: existing.isPlaying || application.isPlaying,
                isBypassed: existing.isBypassed,
                selectedOutputDeviceUID: existing.selectedOutputDeviceUID,
                effectiveOutputDeviceUID: existing.effectiveOutputDeviceUID,
                outputDeviceUnavailable: existing.outputDeviceUnavailable,
                volume: existing.volume
            )
        }

        return merged
    }

    /// The volume of a row: from disk when the row has a key to save under, otherwise from this
    /// session only.
    static func storedVolume(
        for identity: MixerRowIdentity,
        saved: [String: Double],
        session: [String: Double]
    ) -> Double? {
        guard let key = identity.persistenceID else { return session[identity.rowID] }
        return saved[key]
    }

    static func storedRoute(
        for identity: MixerRowIdentity,
        saved: [String: String],
        session: [String: String]
    ) -> String? {
        guard let key = identity.persistenceID else { return session[identity.rowID] }
        return saved[key]
    }

    // MARK: - Headphone disconnect protection

    /// Turns the speakers down when headphones go away, and hands the level back when they
    /// return. Runs as part of a refresh, because reading and writing a device's volume are both
    /// HAL calls and this fires exactly when the audio daemon is busiest.
    static func loweringVolumeIfHeadphonesDisconnected(
        state: MixerLoweredOutputState,
        previousDefaultUID: String?,
        previousOutputDevices: [MixerOutputDevice],
        nextDefaultUID: String?,
        nextOutputDevices: [MixerOutputDevice],
        lowersOnDisconnect: Bool,
        lowerToPercent: Int
    ) -> MixerLoweredOutputState {
        var state = state

        if let nextDefaultUID,
           nextOutputDevices.first(where: { $0.uid == nextDefaultUID })?.isHeadphones == true {
            state.lastAutomaticallyLoweredOutputUID = nil
            // Headphones are back: the speakers get the level they had before the disconnect.
            state.loweredOutput = restoringLoweredVolume(state.loweredOutput, in: nextOutputDevices)
            return state
        }

        guard lowersOnDisconnect,
              let previousDefaultUID,
              let previousDefault = previousOutputDevices.first(where: { $0.uid == previousDefaultUID }),
              previousDefault.isHeadphones,
              nextOutputDevices.contains(where: {
                  $0.uid == previousDefaultUID && $0.isHeadphones
              }) == false,
              let nextDefaultUID,
              let nextDefault = nextOutputDevices.first(where: { $0.uid == nextDefaultUID }),
              nextDefault.isHeadphones == false,
              state.lastAutomaticallyLoweredOutputUID != nextDefaultUID else {
            return state
        }

        let volume = Float32(Double(lowerToPercent) / 100)
        let previousVolume = CoreAudioProperties.outputVolume(for: nextDefault.objectID)
        if CoreAudioProperties.setOutputVolume(volume, for: nextDefault.objectID) {
            state.lastAutomaticallyLoweredOutputUID = nextDefaultUID
            if let previousVolume, previousVolume > volume {
                state.loweredOutput = MixerLoweredOutputState.LoweredOutput(
                    uid: nextDefaultUID,
                    previousVolume: previousVolume,
                    appliedVolume: volume
                )
            }
        }
        return state
    }

    /// Puts back the volume this feature lowered, as long as it is still the value the mixer
    /// set. Returns what is left to restore later.
    static func restoringLoweredVolume(
        _ lowered: MixerLoweredOutputState.LoweredOutput?,
        in devices: [MixerOutputDevice]
    ) -> MixerLoweredOutputState.LoweredOutput? {
        guard let lowered else { return nil }
        guard let device = devices.first(where: { $0.uid == lowered.uid }) else {
            // The device is not around to restore right now; it may come back.
            return lowered
        }
        guard MixerRoutingRules.shouldRestoreOutputVolume(
            appliedVolume: Double(lowered.appliedVolume),
            currentVolume: CoreAudioProperties.outputVolume(for: device.objectID).map(Double.init)
        ) else { return nil }
        CoreAudioProperties.setOutputVolume(lowered.previousVolume, for: device.objectID)
        return nil
    }
}
