import CoreAudio
import Foundation

/// An output device the mixer can send audio to.
nonisolated struct MixerOutputDevice: Identifiable, Equatable, Sendable {
    /// Stable identity: the device's CoreAudio UID.
    let id: String
    let uid: String
    let name: String
    /// Currently the system's default output.
    let isDefault: Bool
    /// Looks like headphones, which is what the disconnect protection watches for.
    let isHeadphones: Bool
    let canBeDefaultOutput: Bool
    let canBeDefaultSystemOutput: Bool
    /// The live HAL object. Valid only while the device is attached.
    let objectID: AudioObjectID
}

/// An input device the mixer can choose for the system.
nonisolated struct MixerInputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    let objectID: AudioObjectID
}

/// How a mixer row is identified.
///
/// `rowID` identifies the row and its engine for as long as the app runs. `persistenceID` is the
/// key its volume and route are stored under: the bundle identifier when the process has one,
/// otherwise its display name, which is the only handle that survives a relaunch — process
/// identifiers are recycled. A process with neither is still listed and adjustable, but nothing
/// about it is written to disk.
nonisolated struct MixerRowIdentity: Equatable, Sendable {
    let rowID: String
    let persistenceID: String?
}

/// One application in the mixer: every audio-producing process it is responsible for, rolled
/// into a single row.
nonisolated struct MixerApplication: Identifiable, Equatable, Sendable {
    let id: String
    let persistenceID: String?
    let ownerProcessID: pid_t
    let name: String
    /// The HAL process objects this row covers.
    let audioObjects: [AudioObjectID]
    /// True while the app is emitting sound right now. Apps stay listed between sounds as long
    /// as they hold an audio connection, so their slider does not come and go.
    let isPlaying: Bool
    /// The app drives its own audio path (conferencing apps, audio workstations). It is listed,
    /// because its absence reads as a bug, but never tapped: no slider, no routing, unity gain.
    var isBypassed: Bool = false
    var selectedOutputDeviceUID: String?
    var effectiveOutputDeviceUID: String?
    /// The chosen output is not attached right now, so the row falls back to the default.
    var outputDeviceUnavailable: Bool
    /// `0...2`, where `1` is untouched passthrough and anything above it is a boost.
    var volume: Double

    var identity: MixerRowIdentity {
        MixerRowIdentity(rowID: id, persistenceID: persistenceID)
    }
}

/// An application the user took off the mixer list, remembered by name so it can be brought back
/// while it is not running.
nonisolated struct MixerHiddenApplication: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}
