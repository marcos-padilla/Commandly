import AudioToolbox
import CoreAudio
import Foundation

/// Thin, typed access to the CoreAudio HAL used by the mixer.
///
/// Everything here is a synchronous property read or write. A device being reconfigured can hold
/// a single read for as long as the audio daemon holds that device, so callers run these off the
/// main actor.
nonisolated enum CoreAudioProperties {
    /// Name given to the mixer's private aggregate devices, so they are never offered as outputs.
    static let aggregateDeviceName = "Commandly Mixer"

    /// Volume selectors tried in order: the virtual main control first, then the raw scalar.
    static let outputVolumeSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyVolumeScalar,
    ]

    /// The mute switch sits on the device as a whole or on each channel, depending on the
    /// driver, so both are tried.
    private static let muteElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain, 1, 2,
    ]

    // MARK: - Generic reads

    @discardableResult
    static func read<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ value: inout T,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer)
            ) == noErr
        }
    }

    static func readList(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return objects
    }

    static func readString(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var reference: CFString = "" as CFString
        guard read(object, selector, &reference, scope: scope) else { return nil }
        let value = reference as String
        return value.isEmpty ? nil : value
    }

    // MARK: - Device enumeration

    static func outputDevices(defaultUID: String?) -> [MixerOutputDevice] {
        let deviceIDs = readList(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDevices
        )

        var devices: [MixerOutputDevice] = []
        for deviceID in deviceIDs {
            guard hasStreams(deviceID, scope: kAudioObjectPropertyScopeOutput) else { continue }
            guard isAlive(deviceID), isHidden(deviceID) == false else { continue }
            guard let uid = readString(deviceID, kAudioDevicePropertyDeviceUID) else { continue }

            let name = readString(deviceID, kAudioObjectPropertyName) ?? uid
            // The mixer's own aggregates are private plumbing, never a destination.
            guard name != aggregateDeviceName else { continue }

            devices.append(
                MixerOutputDevice(
                    id: uid,
                    uid: uid,
                    name: name,
                    isDefault: uid == defaultUID,
                    isHeadphones: MixerRoutingRules.outputLooksLikeHeadphones(
                        name: name,
                        uid: uid,
                        dataSourceName: dataSourceName(for: deviceID, scope: kAudioObjectPropertyScopeOutput)
                    ),
                    canBeDefaultOutput: canBeDefault(
                        deviceID,
                        selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                        scope: kAudioObjectPropertyScopeOutput
                    ),
                    canBeDefaultSystemOutput: canBeDefault(
                        deviceID,
                        selector: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
                        scope: kAudioObjectPropertyScopeOutput
                    ),
                    objectID: deviceID
                )
            )
        }

        return devices.sorted { lhs, rhs in
            MixerRoutingRules.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid
            )
        }
    }

    static func inputDevices(defaultUID: String?) -> [MixerInputDevice] {
        let deviceIDs = readList(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDevices
        )

        var devices: [MixerInputDevice] = []
        for deviceID in deviceIDs {
            guard hasStreams(deviceID, scope: kAudioObjectPropertyScopeInput) else { continue }
            guard isAlive(deviceID), isHidden(deviceID) == false else { continue }
            guard canBeDefault(
                deviceID,
                selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                scope: kAudioObjectPropertyScopeInput
            ) else { continue }
            guard let uid = readString(deviceID, kAudioDevicePropertyDeviceUID) else { continue }

            let name = readString(deviceID, kAudioObjectPropertyName) ?? uid
            guard name != aggregateDeviceName else { continue }

            devices.append(
                MixerInputDevice(
                    id: uid,
                    uid: uid,
                    name: name,
                    isDefault: uid == defaultUID,
                    objectID: deviceID
                )
            )
        }

        return devices.sorted { lhs, rhs in
            MixerRoutingRules.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid
            )
        }
    }

    private static func hasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    private static func isAlive(_ deviceID: AudioObjectID) -> Bool {
        var value: UInt32 = 1
        guard read(deviceID, kAudioDevicePropertyDeviceIsAlive, &value) else { return true }
        return value != 0
    }

    private static func isHidden(_ deviceID: AudioObjectID) -> Bool {
        var value: UInt32 = 0
        guard read(deviceID, kAudioDevicePropertyIsHidden, &value) else { return false }
        return value != 0
    }

    private static func canBeDefault(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var value: UInt32 = 0
        return read(deviceID, selector, &value, scope: scope) && value != 0
    }

    /// The device's current data source name ("Headphones", "Internal Speakers"), which is what
    /// distinguishes a headphone jack from the speakers behind the same device.
    private static func dataSourceName(
        for deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var dataSourceID: UInt32 = 0
        guard read(deviceID, kAudioDevicePropertyDataSource, &dataSourceID, scope: scope) else {
            return nil
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &dataSourceID) { sourcePointer in
            withUnsafeMutablePointer(to: &name) { namePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(sourcePointer),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(namePointer),
                    mOutputDataSize: UInt32(MemoryLayout<CFString>.size)
                )
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &translation)
            }
        }
        guard status == noErr else { return nil }
        let value = name as String
        return value.isEmpty ? nil : value
    }

    // MARK: - Default devices

    static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var device = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject), selector, &device), device != 0 else {
            return nil
        }
        return device
    }

    static func defaultDeviceUID(selector: AudioObjectPropertySelector) -> String? {
        guard let device = defaultDeviceID(selector: selector) else { return nil }
        return readString(device, kAudioDevicePropertyDeviceUID)
    }

    static func setDefaultDevice(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> OSStatus {
        var nextDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &nextDeviceID
        )
    }

    // MARK: - Output volume and mute

    static func outputVolume(for deviceID: AudioObjectID) -> Float32? {
        for selector in outputVolumeSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var volume: Float32 = 0
            if read(deviceID, selector, &volume, scope: kAudioObjectPropertyScopeOutput) {
                return volume
            }
        }
        return nil
    }

    static func hasSettableOutputVolume(for deviceID: AudioObjectID) -> Bool {
        for selector in outputVolumeSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var isSettable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
               isSettable.boolValue {
                return true
            }
        }
        return false
    }

    @discardableResult
    static func setOutputVolume(_ volume: Float32, for deviceID: AudioObjectID) -> Bool {
        let clamped = min(max(volume, 0), 1)
        for selector in outputVolumeSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            var isSettable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
                  isSettable.boolValue else { continue }

            var nextVolume = clamped
            if AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &nextVolume
            ) == noErr {
                return true
            }
        }
        return false
    }

    static func outputMuted(for deviceID: AudioObjectID) -> Bool? {
        for element in muteElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
            else { continue }
            return value != 0
        }
        return nil
    }

    @discardableResult
    static func setOutputMuted(_ muted: Bool, for deviceID: AudioObjectID) -> Bool {
        var changed = false
        for element in muteElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var isSettable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
                  isSettable.boolValue else { continue }
            var value: UInt32 = muted ? 1 : 0
            if AudioObjectSetPropertyData(
                deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
            ) == noErr {
                changed = true
            }
        }
        return changed
    }

    // MARK: - System-wide shortcuts

    /// System volume as people mean it: the default output device's main scalar.
    ///
    /// Static so callers such as a keyboard shortcut never have to spin the mixer up. Returns
    /// `false` when the device exposes no software volume control.
    @discardableResult
    static func setSystemOutputVolume(_ volume: Double) -> Bool {
        guard let device = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice) else {
            return false
        }
        let clamped = Float32(min(max(volume, 0), 1))
        let applied = setOutputVolume(clamped, for: device)
        // Mute is a separate switch from the level, so asking for sound means asking for sound.
        if clamped > 0 { setOutputMuted(false, for: device) }
        return applied
    }

    static func systemOutputVolume() -> Double? {
        guard let device = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        else { return nil }
        return outputVolume(for: device).map(Double.init)
    }

    static func systemOutputIsMuted() -> Bool? {
        guard let device = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        else { return nil }
        return outputMuted(for: device)
    }

    @discardableResult
    static func setSystemOutputMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        else { return false }
        return setOutputMuted(muted, for: device)
    }

    // MARK: - Audio processes

    static func audioProcessObjects() -> [AudioObjectID] {
        readList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    /// The bundle identifier the HAL itself reports for a process object.
    ///
    /// Used only to fill in an identity the running-application lookup could not provide, never
    /// to override it.
    static func processBundleIdentifier(of object: AudioObjectID) -> String? {
        guard #available(macOS 14.4, *) else { return nil }
        return readString(object, kAudioProcessPropertyBundleID)
    }

    static func isRunningOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func nominalSampleRateAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// The rate a device renders at, for the limiter's release timing. A failed read falls back
    /// to the common device rate; being off by one device's rate shifts the release by
    /// milliseconds.
    static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate),
              sampleRate > 0 else { return 48_000 }
        return sampleRate
    }

    /// Total output channels a device presents, used to size the limiter's delay line before the
    /// realtime callback starts.
    static func outputChannelCapacity(of deviceID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 2 }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else {
            return 2
        }
        let buffers = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)
        )
        return max(2, buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
    }
}
