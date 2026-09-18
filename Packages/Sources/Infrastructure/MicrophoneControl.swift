import Foundation

/// The current system mute state of the Mac's default audio input device.
public struct MicrophoneControlState: Sendable, Equatable {
    /// User-visible name reported by Core Audio for the default input device.
    public let deviceName: String
    /// Whether every address controlled by the device's mute property is muted.
    ///
    /// `nil` means the device does not expose a readable system mute property.
    public let isMuted: Bool?
    /// Whether the device's mute property can be changed.
    public let canChangeMute: Bool

    public init(deviceName: String, isMuted: Bool?, canChangeMute: Bool) {
        self.deviceName = deviceName
        self.isMuted = isMuted
        self.canChangeMute = canChangeMute
    }
}

/// Typed failures produced while inspecting or changing the default audio input device.
public enum MicrophoneControlError: Error, Sendable, Equatable {
    case noDefaultInputDevice
    case hardwareFailure(operation: String, status: Int32)
    case muteControlUnavailable(deviceName: String)
}

/// Reads and changes the system mute property of the default audio input device.
///
/// Implementations control device state only. They must never capture audio samples or request
/// microphone recording permission as part of this contract.
public protocol MicrophoneControlling: Sendable {
    /// Returns the current default device and its system mute capability.
    func state() async throws -> MicrophoneControlState
    /// Sets system mute on the current default input device and returns the resulting state.
    func setMuted(_ isMuted: Bool) async throws -> MicrophoneControlState
}

