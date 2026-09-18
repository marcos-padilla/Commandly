import CoreAudio
import Foundation

/// Pure decision rules behind the volume mixer.
///
/// Routing, identity, visibility, and engine-health decisions are all plain functions of their
/// inputs, so they can be exercised without a single audio device attached.
nonisolated enum MixerRoutingRules {
    /// Selection value that means "follow the system default output".
    static let systemDefaultSelectionID = "__system_default__"
    static let finderBundleIdentifier = "com.apple.finder"
    /// Row identifier prefix for a process with no bundle identifier.
    static let unidentifiedRowPrefix = "process:"
    /// Volumes run `0...2`: `1` is untouched passthrough, up to `2` is a 200% boost.
    static let maximumVolume: Double = 2

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)

    // MARK: - Volume values

    /// A volume the UI would round to 100% counts as untouched, so dragging near 100% restores
    /// true passthrough instead of leaving a tap running at an inaudible difference.
    static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
    }

    static func sanitizedApplicationVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), maximumVolume)
    }

    /// Turns text typed beside a slider into a gain. The field accepts the same optional percent
    /// sign it displays; the caller supplies the ceiling (100 for system output, 200 for a row).
    static func volumeFraction(fromPercentageText text: String, maximumPercent: Int) -> Double? {
        guard maximumPercent >= 0 else { return nil }
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("%") {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let separator = Locale.current.decimalSeparator, separator != "." {
            normalized = normalized.replacingOccurrences(of: separator, with: ".")
        }
        guard let percent = Double(normalized), percent.isFinite else { return nil }
        return min(max(percent, 0), Double(maximumPercent)) / 100
    }

    // MARK: - Sanitizing stored values

    static func sanitizedIdentifier(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.count <= 512 else { return nil }
        guard trimmed.unicodeScalars.contains(where: forbiddenScalars.contains) == false else {
            return nil
        }
        return trimmed
    }

    static func sanitizedDeviceUID(_ value: Any?) -> String? {
        sanitizedIdentifier(value as? String)
    }

    static func sanitizedRouteMap(_ raw: [String: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (rawID, rawUID) in raw {
            guard let rowID = sanitizedIdentifier(rawID),
                  let deviceUID = sanitizedDeviceUID(rawUID) else { continue }
            sanitized[rowID] = deviceUID
        }
        return sanitized
    }

    static func sanitizedVolumeMap(_ raw: [String: Any]) -> [String: Double] {
        var sanitized: [String: Double] = [:]
        for (rawID, rawValue) in raw {
            guard let rowID = sanitizedIdentifier(rawID) else { continue }
            let number: Double?
            if let value = rawValue as? Double {
                number = value
            } else if let value = rawValue as? NSNumber {
                number = value.doubleValue
            } else {
                number = nil
            }
            guard let number, number.isFinite else { continue }
            sanitized[rowID] = sanitizedApplicationVolume(number)
        }
        return sanitized
    }

    /// The hidden-apps map as stored: persistence id to display name.
    ///
    /// The Finder entry never lives here — its visibility has its own preference — so an entry
    /// for it is dropped rather than shadowing that preference.
    static func sanitizedHiddenApplications(_ raw: [String: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (rawID, rawName) in raw {
            guard let rowID = sanitizedIdentifier(rawID),
                  rowID != finderBundleIdentifier,
                  let name = sanitizedIdentifier(rawName as? String) else { continue }
            sanitized[rowID] = name
        }
        return sanitized
    }

    static func sanitizedDeviceUIDList(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { value in
            guard let uid = sanitizedDeviceUID(value), seen.insert(uid).inserted else { return nil }
            return uid
        }
    }

    // MARK: - Row identity and visibility

    /// Identity of a row: the bundle identifier when the app has one, otherwise a per-process row
    /// saved under its display name.
    ///
    /// Tools distributed as bare executables have no bundle identifier, and the name is the only
    /// stable key left. Two same-named processes stay separate rows but share a saved volume.
    static func rowIdentity(
        bundleIdentifier: String?,
        ownerProcessID: pid_t,
        displayName: String?
    ) -> MixerRowIdentity {
        guard let bundleID = sanitizedIdentifier(bundleIdentifier) else {
            return MixerRowIdentity(
                rowID: "\(unidentifiedRowPrefix)\(ownerProcessID)",
                persistenceID: sanitizedIdentifier(displayName)
            )
        }
        return MixerRowIdentity(rowID: bundleID, persistenceID: bundleID)
    }

    /// Every persistence id a refresh must leave out: the apps the user hid, plus the Finder
    /// while its own preference says so.
    static func hiddenRowIDs(hiddenApplications: [String: String], showsFinder: Bool) -> Set<String> {
        var ids = Set(hiddenApplications.keys)
        if showsFinder == false { ids.insert(finderBundleIdentifier) }
        return ids
    }

    /// A row with no persistence id cannot be hidden: there is no stable key to remember it by.
    static func isHidden(persistenceID: String?, hiddenIDs: Set<String>) -> Bool {
        guard let persistenceID else { return false }
        return hiddenIDs.contains(persistenceID)
    }

    static func needsPersistentFinderRow(showsFinder: Bool, hasFinderRow: Bool) -> Bool {
        showsFinder && hasFinderRow == false
    }

    /// Inactive apps that carry a custom volume or output stay visible, so hiding idle rows can
    /// never conceal a setting the user may want to undo.
    static func shouldShowApplication(
        isPlaying: Bool,
        volume: Double,
        selectedOutputDeviceUID: String?,
        hidesInactiveApplications: Bool
    ) -> Bool {
        guard hidesInactiveApplications else { return true }
        return isPlaying || isUnity(volume) == false || selectedOutputDeviceUID != nil
    }

    /// Ordering for mixer rows: display name, then id. Swift's sort is not stable, so two apps
    /// with the same name need the explicit tie-break or their rows swap between refreshes.
    static func displayOrderedBefore(
        name: String,
        id: String,
        otherName: String,
        otherID: String
    ) -> Bool {
        switch name.localizedCaseInsensitiveCompare(otherName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return id < otherID
        }
    }

    /// Ordering for device lists: the default first, then name, then uid.
    static func deviceDisplayOrderedBefore(
        isDefault: Bool,
        name: String,
        uid: String,
        otherIsDefault: Bool,
        otherName: String,
        otherUID: String
    ) -> Bool {
        if isDefault != otherIsDefault { return isDefault }
        return displayOrderedBefore(name: name, id: uid, otherName: otherName, otherID: otherUID)
    }

    // MARK: - Ownership

    /// How many parent processes to inspect when the responsible process is not a regular app.
    static let owningApplicationSearchDepth = 6

    /// The regular app a helper's audio belongs to.
    ///
    /// Normally that is the helper's responsible process, but some browsers detach their audio
    /// helpers from the responsibility chain and macOS reports each one as responsible for
    /// itself. The BSD parent chain still leads to the app that spawned the helper, so it is
    /// walked — to a small depth — and the helper is billed to the nearest regular app.
    static func owningRegularApplicationID(
        responsibleProcessID: pid_t,
        isRegularApplication: (pid_t) -> Bool,
        parentProcessID: (pid_t) -> pid_t
    ) -> pid_t? {
        guard responsibleProcessID > 0 else { return nil }
        if isRegularApplication(responsibleProcessID) { return responsibleProcessID }
        var current = responsibleProcessID
        for _ in 0..<owningApplicationSearchDepth {
            current = parentProcessID(current)
            guard current > 1 else { return nil }
            if isRegularApplication(current) { return current }
        }
        return nil
    }

    /// Bundle-identifier prefixes of apps that own their output device, clock, and latency chain.
    ///
    /// A stereo-mixdown tap mutes their real output and replays it elsewhere, which silences
    /// them outright, so they are listed but never tapped.
    private static let selfDrivenAudioBundlePrefixes = [
        "com.apple.logic",
        "com.apple.garageband",
        "com.apple.mainstage",
        "com.ableton.",
        "com.avid.",
        "com.cockos.reaper",
        "com.steinberg.",
        "com.presonus.",
        "com.bitwig.",
        "com.image-line.",
        "com.motu.",
    ]

    static func bypassesProcessTap(bundleIdentifier: String?, name: String) -> Bool {
        let bundle = normalized(bundleIdentifier ?? "")
        if bundle.hasPrefix("us.zoom.") { return true }
        if selfDrivenAudioBundlePrefixes.contains(where: bundle.hasPrefix) { return true }

        let normalizedName = normalized(name).trimmingCharacters(in: .whitespacesAndNewlines)
        return ["zoom", "zoom.us", "zoom workplace"].contains(normalizedName)
    }

    // MARK: - Routing

    static func effectiveDeviceUID(
        selectedUID: String?,
        availableUIDs: Set<String>,
        defaultUID: String?
    ) -> String? {
        if let selectedUID, availableUIDs.contains(selectedUID) { return selectedUID }
        return defaultUID
    }

    static func selectedDeviceUnavailable(selectedUID: String?, availableUIDs: Set<String>) -> Bool {
        guard let selectedUID else { return false }
        return availableUIDs.contains(selectedUID) == false
    }

    /// Whether a row needs a tap at all. A row on the system default output at unity gain is
    /// left completely untouched.
    static func requiresEngine(
        hasAudioObjects: Bool = true,
        volume: Double,
        selectedOutputDeviceUID: String?,
        targetOutputDeviceUID: String?,
        defaultOutputDeviceUID: String?
    ) -> Bool {
        guard hasAudioObjects, targetOutputDeviceUID != nil else { return false }
        if isUnity(volume) == false { return true }
        guard let selectedOutputDeviceUID else { return false }
        guard let defaultOutputDeviceUID else { return true }
        return selectedOutputDeviceUID != defaultOutputDeviceUID
            && targetOutputDeviceUID != defaultOutputDeviceUID
    }

    /// The last gate before a tap is built: a row is tapped only when the user actually adjusted
    /// it. An app that is merely listed is never part of any tap, so the mixer can neither mute
    /// it nor re-render its sound.
    static func rowMayBeTapped(
        savedVolume: Double?,
        savedRouteUID: String?,
        defaultOutputDeviceUID: String?
    ) -> Bool {
        if let savedVolume, isUnity(savedVolume) == false { return true }
        guard let savedRouteUID else { return false }
        guard let defaultOutputDeviceUID else { return true }
        return savedRouteUID != defaultOutputDeviceUID
    }

    /// Per-row routes after the whole system output changed: every row goes back to following
    /// the new default, because the user just chose it for everything.
    static func routesAfterSystemOutputSwitch(
        routes: [String: String],
        switchSucceeded: Bool
    ) -> [String: String] {
        switchSucceeded ? [:] : routes
    }

    /// The next output in the user's chosen cycle, or `nil` when there is nowhere to go.
    static func nextSelectedOutputDeviceUID(
        currentUID: String?,
        selectedUIDs: [String],
        availableUIDs: Set<String>
    ) -> String? {
        var seen = Set<String>()
        let candidates = selectedUIDs.compactMap { rawUID -> String? in
            guard let uid = sanitizedDeviceUID(rawUID),
                  availableUIDs.contains(uid),
                  seen.insert(uid).inserted else { return nil }
            return uid
        }
        guard candidates.isEmpty == false else { return nil }
        guard let currentUID, let index = candidates.firstIndex(of: currentUID) else {
            return candidates[0]
        }
        guard candidates.count > 1 else { return nil }
        return candidates[(index + 1) % candidates.count]
    }

    static func outputLooksLikeHeadphones(name: String, uid: String, dataSourceName: String?) -> Bool {
        let haystack = normalized([name, uid, dataSourceName ?? ""].joined(separator: " "))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        let terms = [
            "headphone", "headphones", "headset",
            "earphone", "earphones", "earbud", "earbuds",
            "airpod", "airpods", "earpod", "earpods",
            "galaxy buds", "pixel buds", "beats", "bose qc",
            "sony wh", "sony wf", "jabra", "soundcore",
        ]
        return terms.contains(where: haystack.contains)
    }

    /// A volume the mixer lowered on its own only goes back up while it is still the value the
    /// mixer set. Anything else means it was changed since, and that choice wins.
    static func shouldRestoreOutputVolume(appliedVolume: Double, currentVolume: Double?) -> Bool {
        guard let currentVolume else { return false }
        return abs(currentVolume - appliedVolume) < 0.005
    }

    /// What to put back as the system input when the mixer stops steering it. `nil` means leave
    /// the system alone.
    static func restorableInputDeviceUID(
        originalUID: String?,
        appliedUID: String?,
        currentUID: String?,
        availableUIDs: Set<String>
    ) -> String? {
        guard let originalUID, let appliedUID, originalUID != appliedUID else { return nil }
        guard currentUID == appliedUID, availableUIDs.contains(originalUID) else { return nil }
        return originalUID
    }

    static func resolveInputDevice(
        preferredUID: String?,
        availableUIDs: Set<String>,
        currentUID: String?
    ) -> MixerInputRouteResolution {
        guard let preferredUID else {
            return MixerInputRouteResolution(
                effectiveUID: currentUID,
                selectedUnavailable: false,
                shouldApplyPreferred: false
            )
        }
        guard availableUIDs.contains(preferredUID) else {
            return MixerInputRouteResolution(
                effectiveUID: currentUID,
                selectedUnavailable: true,
                shouldApplyPreferred: false
            )
        }
        return MixerInputRouteResolution(
            effectiveUID: preferredUID,
            selectedUnavailable: false,
            shouldApplyPreferred: preferredUID != currentUID
        )
    }

    // MARK: - Engine health

    /// Window used to fold a row's comings and goings into one decision.
    static let engineChurnCoalescingWindow: Double = 0.2

    /// How long to keep an engine whose row has no audio object left; `nil` means let it go now.
    ///
    /// An app that recreates its audio unit between clips loses its audio object and gets a new
    /// one moments later. Nothing is audible in that gap, so the tap is kept for a short window
    /// and the churn folds into one decision instead of a teardown per notification.
    static func engineTeardownDelay(
        hasAudioObjects: Bool,
        lastChangeAt: Double?,
        now: Double,
        window: Double = engineChurnCoalescingWindow
    ) -> Double? {
        guard hasAudioObjects == false else { return nil }
        guard let lastChangeAt else { return window }
        let elapsed = max(0, now - lastChangeAt)
        guard elapsed < window else { return nil }
        return window - elapsed
    }

    /// One look at an engine's render counter.
    struct EngineRenderObservation: Equatable, Sendable {
        let cycles: UInt64
        let at: Double
    }

    enum EngineRenderVerdict: Equatable, Sendable {
        /// Remember this observation. A non-nil `recheckAfter` means the picture is not
        /// conclusive yet, so another look is scheduled rather than waiting for an audio event.
        case note(EngineRenderObservation, recheckAfter: Double?)
        /// The counter has not moved, but not for long enough to be sure.
        case stalled(recheckAfter: Double)
        /// The app is playing and the engine rendered nothing for the whole window: its audio
        /// path is dead and only the mute remains.
        case wedged
    }

    /// How long a live engine may go without a render callback, while its app is playing, before
    /// it counts as wedged. A healthy aggregate runs its IO proc hundreds of times a second.
    static let engineRenderStallWindow: Double = 1.5

    /// Whether an engine is still rendering.
    ///
    /// Waking from sleep can leave an aggregate whose IO proc never runs again while its tap
    /// keeps muting the app, and nothing else about the engine looks wrong. Only a playing app
    /// gives a verdict: with no audio there is nothing to mute, and a counter naturally at rest
    /// must not read as a failure.
    static func engineRenderVerdict(
        previous: EngineRenderObservation?,
        cycles: UInt64,
        isPlaying: Bool,
        now: Double,
        window: Double = engineRenderStallWindow
    ) -> EngineRenderVerdict? {
        guard isPlaying else { return nil }
        guard let previous else {
            return .note(EngineRenderObservation(cycles: cycles, at: now), recheckAfter: window)
        }
        guard cycles == previous.cycles else {
            return .note(EngineRenderObservation(cycles: cycles, at: now), recheckAfter: nil)
        }
        let elapsed = max(0, now - previous.at)
        guard elapsed >= window else { return .stalled(recheckAfter: window - elapsed) }
        return .wedged
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}

/// How a preferred input device resolves against what is actually attached.
nonisolated struct MixerInputRouteResolution: Equatable, Sendable {
    let effectiveUID: String?
    let selectedUnavailable: Bool
    let shouldApplyPreferred: Bool
}
