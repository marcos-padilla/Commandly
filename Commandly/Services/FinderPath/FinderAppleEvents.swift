import CoreServices
import Foundation
import Infrastructure

/// Only these fixed read operations can cross the native boundary; no caller supplies event codes.
nonisolated enum FinderEventQuery: Sendable, Equatable {
    case frontWindowID, selection
    case folderClass(windowID: Int32), folderURL(windowID: Int32)
    case selectedURL(reference: Data)
}
nonisolated enum FinderEventValue: Sendable, Equatable {
    case integer(Int32), typeCode(UInt32), selection(Data?), text(String)
}
nonisolated protocol FinderAppleEventTransport: Sendable {
    func authorization(pid: Int32, allowPrompt: Bool) throws -> FinderPathAuthorization
    func read(_ query: FinderEventQuery, pid: Int32, timeout: TimeInterval) throws -> FinderEventValue
}

/// The fixed codes below are from the installed Apple Finder.sdef and public Apple Event headers.
nonisolated enum FinderAppleEventCodec {
    static let core: UInt32 = 0x636F7265 // core
    static let getData: UInt32 = 0x67657464 // getd
    static let object: UInt32 = 0x6F626A20 // obj
    static let list: UInt32 = 0x6C697374 // list
    static let directObject: UInt32 = 0x2D2D2D2D // ----
    static let errorNumber: UInt32 = 0x6572726E // errn
    static let selectionProperty: UInt32 = 0x73656C65 // sele
    static let urlProperty: UInt32 = 0x7055524C // pURL
    static let targetProperty: UInt32 = 0x66767467 // fvtg
    static let classProperty: UInt32 = 0x70636C73 // pcls
    static let windowClass: UInt32 = 0x62726F77 // brow
    static let windowIDProperty: UInt32 = 0x49442020 // ID
    static let maximumReplyBytes = 65_536
    static let maximumReferenceBytes = 32_768

    static func event(_ query: FinderEventQuery, pid: Int32) throws -> NSAppleEventDescriptor {
        guard pid > 0 else { throw FinderPathError.finderUnavailable }
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let direct: NSAppleEventDescriptor
        switch query {
        case .frontWindowID:
            direct = try property(windowIDProperty, of: element(windowClass, form: 0x696E6478, key: .init(int32: 1)))
        case .selection:
            direct = try property(selectionProperty, of: .null())
        case .folderClass(let id):
            direct = try property(classProperty, of: folder(id))
        case .folderURL(let id):
            direct = try property(urlProperty, of: folder(id))
        case .selectedURL(let data):
            guard !data.isEmpty, data.count <= maximumReferenceBytes,
                  let selected = NSAppleEventDescriptor(descriptorType: object, data: data) else { throw FinderPathError.invalidReply }
            direct = try property(urlProperty, of: selected)
        }
        let event = NSAppleEventDescriptor(eventClass: core, eventID: getData, targetDescriptor: target,
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(direct, forKeyword: directObject)
        return event
    }
    private static func folder(_ windowID: Int32) throws -> NSAppleEventDescriptor {
        guard windowID > 0 else { throw FinderPathError.noWindow }
        return try property(targetProperty, of: element(windowClass, form: 0x49442020, key: .init(int32: windowID)))
    }
    private static func property(_ code: UInt32, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try element(0x70726F70, form: 0x70726F70, key: .init(typeCode: code), container: container) // prop
    }
    private static func element(_ desiredClass: UInt32, form: UInt32, key: NSAppleEventDescriptor,
                                container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: desiredClass), forKeyword: 0x77616E74) // want
        record.setDescriptor(.init(enumCode: form), forKeyword: 0x666F726D) // form
        record.setDescriptor(key, forKeyword: 0x73656C64) // seld
        record.setDescriptor(container, forKeyword: 0x66726F6D) // from
        guard let value = record.coerce(toDescriptorType: object) else { throw FinderPathError.invalidReply }
        return value
    }
    static func decode(_ reply: NSAppleEventDescriptor, query: FinderEventQuery) throws -> FinderEventValue {
        guard bounded(reply, limit: maximumReplyBytes) else { throw FinderPathError.invalidReply }
        if let failure = reply.paramDescriptor(forKeyword: errorNumber), failure.int32Value != 0 {
            throw mapError(failure.int32Value, query: query)
        }
        guard let value = reply.paramDescriptor(forKeyword: directObject) else { throw FinderPathError.invalidReply }
        switch query {
        case .frontWindowID:
            guard value.descriptorType == typeSInt32, value.int32Value > 0 else { throw FinderPathError.noWindow }
            return .integer(value.int32Value)
        case .selection:
            guard value.descriptorType == list else { throw FinderPathError.invalidReply }
            guard value.numberOfItems <= 1 else { throw FinderPathError.multipleSelection }
            guard value.numberOfItems == 1 else { return .selection(nil) }
            guard let item = value.atIndex(1), item.descriptorType == object,
                  bounded(item, limit: maximumReferenceBytes), !item.data.isEmpty else { throw FinderPathError.invalidReply }
            return .selection(item.data)
        case .folderClass:
            guard value.descriptorType == typeType else { throw FinderPathError.unsupportedLocation }
            return .typeCode(value.typeCodeValue)
        case .folderURL, .selectedURL:
            guard [typeUnicodeText, typeUTF8Text, typeChar].contains(value.descriptorType),
                  bounded(value, limit: FinderPathValidation.maximumURLBytes * 2),
                  let text = value.stringValue, text.utf8.count <= FinderPathValidation.maximumURLBytes else {
                throw FinderPathError.unsupportedLocation
            }
            return .text(text)
        }
    }
    private static func bounded(_ descriptor: NSAppleEventDescriptor, limit: Int) -> Bool {
        guard let raw = descriptor.aeDesc else { return false }
        let size = AEGetDescDataSize(raw)
        return size >= 0 && size <= limit
    }
    static func mapError(_ code: Int32, query: FinderEventQuery?) -> FinderPathError {
        switch code {
        case -1743: .permissionDenied
        case -1744: .permissionRequired
        case -600, -609: .finderUnavailable
        case -1712: .timedOut
        case -1728 where query == .frontWindowID: .noWindow
        case -1728, -1700: .unsupportedLocation
        default: .unavailable
        }
    }
    static func authorization(_ status: Int32) throws -> FinderPathAuthorization {
        switch status {
        case 0: .authorized
        case -1744: .requiresConsent
        case -1743: .denied
        case -600, -609: .finderUnavailable
        default: throw FinderPathError.unavailable
        }
    }
}

/// Synchronous calls are used only on NativeFinderPathProbe's dedicated serial executor.
nonisolated struct NativeFinderAppleEventTransport: FinderAppleEventTransport {
    func authorization(pid: Int32, allowPrompt: Bool) throws -> FinderPathAuthorization {
        try Task.checkCancellation()
        guard pid > 0 else { return .finderUnavailable }
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        guard let raw = target.aeDesc else { throw FinderPathError.unavailable }
        let status = AEDeterminePermissionToAutomateTarget(raw, FinderAppleEventCodec.core, FinderAppleEventCodec.getData, allowPrompt)
        try Task.checkCancellation()
        return try FinderAppleEventCodec.authorization(status)
    }
    func read(_ query: FinderEventQuery, pid: Int32, timeout: TimeInterval) throws -> FinderEventValue {
        try Task.checkCancellation()
        return try autoreleasepool {
            let event = try FinderAppleEventCodec.event(query, pid: pid)
            do {
                // Do not prompt after a preflight/revocation race or reconnect/launch a dead process.
                let flags = UInt(kAEWaitReply | kAENeverInteract | kAEDontRecord | kAEDontReconnect | kAEDoNotPromptForUserConsent)
                let reply = try event.sendEvent(options: .init(rawValue: flags), timeout: timeout)
                try Task.checkCancellation()
                return try FinderAppleEventCodec.decode(reply, query: query)
            } catch let failure as FinderPathError { throw failure }
            catch is CancellationError { throw CancellationError() }
            catch { throw FinderAppleEventCodec.mapError(Int32(clamping: (error as NSError).code), query: query) }
        }
    }
}
