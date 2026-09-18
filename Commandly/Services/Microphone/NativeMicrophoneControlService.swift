import CoreAudio
import Foundation
import Infrastructure

/// Core Audio adapter for the system mute property of the current default input device.
actor NativeMicrophoneControlService: MicrophoneControlling {
    func state() async throws -> MicrophoneControlState {
        try readState(for: defaultInputDevice())
    }

    func setMuted(_ isMuted: Bool) async throws -> MicrophoneControlState {
        let device = try defaultInputDevice()
        let deviceName = try readDeviceName(device)
        let addresses = try muteAddresses(for: device)

        guard addresses.isEmpty == false,
              try addresses.allSatisfy({ try isSettable($0, on: device) }) else {
            throw MicrophoneControlError.muteControlUnavailable(deviceName: deviceName)
        }

        let previousValues = try addresses.map { try readMuteValue($0, from: device) }
        var changedAddressCount = 0

        do {
            for address in addresses {
                try writeMuteValue(isMuted, to: address, on: device)
                changedAddressCount += 1
            }
        } catch {
            var rollbackError: Error?
            for index in 0..<changedAddressCount {
                do {
                    try writeMuteValue(previousValues[index], to: addresses[index], on: device)
                } catch {
                    rollbackError = error
                    break
                }
            }
            throw rollbackError ?? error
        }

        return try readState(for: device)
    }

    private func readState(for device: AudioDeviceID) throws -> MicrophoneControlState {
        let deviceName = try readDeviceName(device)
        let addresses = try muteAddresses(for: device)
        guard addresses.isEmpty == false else {
            return MicrophoneControlState(
                deviceName: deviceName,
                isMuted: nil,
                canChangeMute: false
            )
        }

        let values = try addresses.map { try readMuteValue($0, from: device) }
        let canChangeMute = try addresses.allSatisfy { try isSettable($0, on: device) }
        return MicrophoneControlState(
            deviceName: deviceName,
            isMuted: values.allSatisfy { $0 },
            canChangeMute: canChangeMute
        )
    }

    private func defaultInputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        try check(status, operation: "read-default-input-device")
        guard device != kAudioObjectUnknown else {
            throw MicrophoneControlError.noDefaultInputDevice
        }
        return device
    }

    private func readDeviceName(_ device: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // CoreAudio returns a retained CFString for kAudioObjectPropertyName. Receive the
        // raw reference outside ARC storage, then consume the ownership exactly once.
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &name
        )
        try check(status, operation: "read-input-device-name")
        guard let name else { return "Microphone" }
        return name.takeRetainedValue() as String
    }

    private func muteAddresses(
        for device: AudioDeviceID
    ) throws -> [AudioObjectPropertyAddress] {
        var mainAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &mainAddress) {
            return [mainAddress]
        }

        let channelCount = try inputChannelCount(for: device)
        guard channelCount > 0 else { return [] }
        let addresses = (1...channelCount).map { channel in
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: AudioObjectPropertyElement(channel)
            )
        }
        guard addresses.allSatisfy({ address in
            var candidate = address
            return AudioObjectHasProperty(device, &candidate)
        }) else {
            return []
        }
        return addresses
    }

    private func inputChannelCount(for device: AudioDeviceID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        try check(sizeStatus, operation: "read-input-channel-count")
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let dataStatus = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            bufferList
        )
        try check(dataStatus, operation: "read-input-channel-count")
        return UnsafeMutableAudioBufferListPointer(bufferList)
            .reduce(0) { $0 + $1.mNumberChannels }
    }

    private func readMuteValue(
        _ propertyAddress: AudioObjectPropertyAddress,
        from device: AudioDeviceID
    ) throws -> Bool {
        var address = propertyAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        )
        try check(status, operation: "read-input-mute")
        return value != 0
    }

    private func writeMuteValue(
        _ isMuted: Bool,
        to propertyAddress: AudioObjectPropertyAddress,
        on device: AudioDeviceID
    ) throws {
        var address = propertyAddress
        var value: UInt32 = isMuted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
        try check(status, operation: "set-input-mute")
    }

    private func isSettable(
        _ propertyAddress: AudioObjectPropertyAddress,
        on device: AudioDeviceID
    ) throws -> Bool {
        var address = propertyAddress
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(device, &address, &settable)
        try check(status, operation: "inspect-input-mute")
        return settable.boolValue
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw MicrophoneControlError.hardwareFailure(
                operation: operation,
                status: status
            )
        }
    }
}
