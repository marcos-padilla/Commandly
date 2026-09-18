import Foundation
import IOKit

/// Wire format of the AppleSMC user client: a fixed layout the controller expects verbatim.
nonisolated struct AppleSMCParameters {
    var key: UInt32 = 0
    var version = AppleSMCVersion()
    var powerLimits = AppleSMCPowerLimits()
    var keyInfo = AppleSMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

nonisolated struct AppleSMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

nonisolated struct AppleSMCPowerLimits {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var processorLimit: UInt32 = 0
    var graphicsLimit: UInt32 = 0
    var memoryLimit: UInt32 = 0
}

nonisolated struct AppleSMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// Encodes and decodes the numeric formats the System Management Controller reports values in.
nonisolated enum AppleSMCValueDecoder {
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            // Little endian, unlike the fixed-point types below.
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float32(bitPattern: bits))
            return value.isFinite ? value : nil
        case "fpe2" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(
                UInt32(bytes[0]) << 24
                    | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8
                    | UInt32(bytes[3])
            )
        case "ioft" where bytes.count == 8:
            var raw: UInt64 = 0
            for (offset, byte) in bytes.enumerated() {
                raw |= UInt64(byte) << UInt64(offset * 8)
            }
            return Double(raw) / 65_536
        default:
            return nil
        }
    }

    /// Encodes a value in the key's own reported type and size, or `nil` when it does not fit.
    static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        guard value.isFinite, value >= 0 else { return nil }
        switch type {
        case "flt " where size == 4:
            let float = Float32(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [
                UInt8(bits & 0xff),
                UInt8((bits >> 8) & 0xff),
                UInt8((bits >> 16) & 0xff),
                UInt8((bits >> 24) & 0xff),
            ]
        case "fpe2" where size == 2:
            let scaled = (value * 4).rounded()
            guard scaled <= Double(UInt16.max) else { return nil }
            let raw = UInt16(scaled)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui8 " where size == 1:
            guard value.rounded() == value, value <= Double(UInt8.max) else { return nil }
            return [UInt8(value)]
        case "ui16" where size == 2:
            guard value.rounded() == value, value <= Double(UInt16.max) else { return nil }
            let raw = UInt16(value)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        default:
            return nil
        }
    }
}

/// Client for the System Management Controller.
///
/// Reads are used for sensors. The single write path exists only for fan control, refuses any
/// payload that does not match the key's own reported type and size, and can never change key
/// metadata. Opening the user client requires an entitlement App Sandbox does not grant by
/// default, and `init` fails cleanly when it is refused.
///
/// `@unchecked Sendable`: the connection is opened in `init`, closed in `deinit`, and every call
/// in between is a synchronous round trip the owner serializes on one queue.
nonisolated final class AppleSMCClient: @unchecked Sendable {
    struct Key: Sendable {
        let code: UInt32
        let name: String
        let dataSize: UInt32
        let dataType: String
    }

    private var connection: io_connect_t = 0

    /// Selector and command bytes of the SMC user client.
    private static let handleEventSelector: UInt32 = 2
    private static let readKeyCommand: UInt8 = 5
    private static let writeKeyCommand: UInt8 = 6
    private static let keyFromIndexCommand: UInt8 = 8
    private static let keyInfoCommand: UInt8 = 9
    /// The controller never reports a value wider than its fixed payload.
    private static let maximumValueSize: UInt32 = 32

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Enumerates every key whose name passes `filter`, with the size and type needed to read it.
    ///
    /// This walks the whole key table, so it belongs in setup rather than in a sampling tick.
    func keys(where filter: (String) -> Bool) -> [Key] {
        var result: [Key] = []
        for index in 0..<keyCount() {
            var probe = AppleSMCParameters()
            probe.data8 = Self.keyFromIndexCommand
            probe.data32 = UInt32(index)
            guard let named = call(&probe), named.result == 0 else { continue }

            let name = Self.fourCharacterString(named.key)
            guard filter(name) else { continue }

            var infoRequest = AppleSMCParameters()
            infoRequest.key = named.key
            infoRequest.data8 = Self.keyInfoCommand
            guard let info = call(&infoRequest), info.result == 0 else { continue }

            result.append(
                Key(
                    code: named.key,
                    name: name,
                    dataSize: info.keyInfo.dataSize,
                    dataType: Self.fourCharacterString(info.keyInfo.dataType)
                )
            )
        }
        return result
    }

    /// Looks up one key by its four-character name, with the size and type needed to use it.
    ///
    /// Cheaper than enumerating the whole table when the caller already knows what it wants.
    func key(named name: String) -> Key? {
        var probe = AppleSMCParameters()
        probe.key = Self.fourCharacterCode(name)
        probe.data8 = Self.keyInfoCommand
        guard let response = call(&probe), response.result == 0 else { return nil }
        return Key(
            code: probe.key,
            name: name,
            dataSize: response.keyInfo.dataSize,
            dataType: Self.fourCharacterString(response.keyInfo.dataType)
        )
    }

    /// Reads one key in its own reported encoding.
    func readValue(_ key: Key) -> Double? {
        guard let bytes = readBytes(key) else { return nil }
        return AppleSMCValueDecoder.decode(bytes, type: key.dataType)
    }

    private func readBytes(_ key: Key) -> [UInt8]? {
        guard key.dataSize > 0, key.dataSize <= Self.maximumValueSize else { return nil }
        var request = AppleSMCParameters()
        request.key = key.code
        request.keyInfo.dataSize = key.dataSize
        request.data8 = Self.readKeyCommand
        guard let response = call(&request), response.result == 0 else { return nil }
        return withUnsafeBytes(of: response.bytes) { Array($0.prefix(Int(key.dataSize))) }
    }

    /// Writes one value, encoded in the key's own reported type and size.
    ///
    /// The payload must match what the controller says the key holds, so a caller cannot overrun
    /// the fixed payload or write a value the key cannot represent.
    @discardableResult
    func writeValue(_ value: Double, to key: Key) -> Bool {
        guard key.dataSize > 0, key.dataSize <= Self.maximumValueSize,
              let bytes = AppleSMCValueDecoder.encode(
                  value,
                  type: key.dataType,
                  size: Int(key.dataSize)
              ), bytes.count == Int(key.dataSize) else {
            return false
        }

        var request = AppleSMCParameters()
        request.key = key.code
        request.keyInfo.dataSize = key.dataSize
        request.data8 = Self.writeKeyCommand
        withUnsafeMutableBytes(of: &request.bytes) { destination in
            destination.copyBytes(from: bytes)
        }
        guard let response = call(&request) else { return false }
        return response.result == 0
    }

    private func keyCount() -> Int {
        var request = AppleSMCParameters()
        request.key = Self.fourCharacterCode("#KEY")
        request.keyInfo.dataSize = 4
        request.data8 = Self.readKeyCommand
        guard let response = call(&request), response.result == 0 else { return 0 }
        let bytes = withUnsafeBytes(of: response.bytes) { Array($0.prefix(4)) }
        guard bytes.count == 4 else { return 0 }
        return Int(
            UInt32(bytes[0]) << 24
                | UInt32(bytes[1]) << 16
                | UInt32(bytes[2]) << 8
                | UInt32(bytes[3])
        )
    }

    private func call(_ request: inout AppleSMCParameters) -> AppleSMCParameters? {
        var response = AppleSMCParameters()
        var responseSize = MemoryLayout<AppleSMCParameters>.stride
        let status = IOConnectCallStructMethod(
            connection,
            Self.handleEventSelector,
            &request,
            MemoryLayout<AppleSMCParameters>.stride,
            &response,
            &responseSize
        )
        return status == kIOReturnSuccess ? response : nil
    }

    private static func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCharacterString(_ value: UInt32) -> String {
        let characters = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: characters, encoding: .ascii) ?? "????"
    }
}
