import Foundation
import Infrastructure

/// Only the current event and configured state enter this reducer. It does not retain unrelated keys.
public struct CompanionKeyboardEvent: Sendable {
    public enum Kind: Sendable { case down, up, modifierDown, modifierUp, physicalCapsDown, physicalCapsUp, boundary, startOfText }
    public let kind: Kind
    public let keyCode: UInt16
    public let timestamp: TimeInterval
    public let isRepeat: Bool
    public let hasShortcutModifier: Bool
    public let text: String
    public init(_ kind: Kind, keyCode: UInt16 = 0, timestamp: TimeInterval, isRepeat: Bool = false,
                hasShortcutModifier: Bool = false, text: String = "") {
        self.kind = kind; self.keyCode = keyCode; self.timestamp = timestamp; self.isRepeat = isRepeat
        self.hasShortcutModifier = hasShortcutModifier; self.text = text
    }
}
/// Unknown fields are never interpreted as non-editable fields.
public enum CompanionKeyboardField: Sendable { case editable, nonEditable, unknown, secure }
public struct CompanionKeyboardDecision: Sendable {
    public var consume = false
    public var addHyper = false
    public var toggleCapsLock = false
    public var resetModifiers = false
    public var activation: UUID?
    public var expansion: CompanionKeywordExpansion?
    public init() {}
}

/// Deterministic tap/hold and suffix matching, with no timers, event posting, persistence or IPC.
/// A suffix starts only at an observed boundary and is bounded to the longest configured keyword.
public struct CompanionKeyboardStateMachine: Sendable {
    private let configuration: CompanionKeyboardConfiguration
    private var capsDownAt: TimeInterval?
    private var capsWasChord = false
    private var consumedKeys: Set<UInt16> = []
    private var modifierDown: (key: UInt16, at: TimeInterval, clean: Bool)?
    private var previousTap: (key: UInt16, at: TimeInterval)?
    private var suffix = ""
    private var atWordBoundary = false
    private var previousTimestamp: TimeInterval?
    public init(configuration: CompanionKeyboardConfiguration) { self.configuration = configuration }
    public var retainedSuffixLength: Int { suffix.count }
    public mutating func reset() -> CompanionKeyboardDecision {
        var value = CompanionKeyboardDecision(); value.resetModifiers = capsDownAt != nil
        capsDownAt = nil; capsWasChord = false; consumedKeys = []; modifierDown = nil; previousTap = nil
        suffix = ""; atWordBoundary = false; previousTimestamp = nil
        return value
    }
    public mutating func process(_ event: CompanionKeyboardEvent, field: CompanionKeyboardField,
                                 secureInput: Bool = false) -> CompanionKeyboardDecision {
        guard !secureInput, field != .secure, event.timestamp.isFinite else { return reset() }
        var value = CompanionKeyboardDecision()
        if let old = previousTimestamp, event.timestamp < old || event.timestamp - old > 5 {
            value = reset()
        }
        previousTimestamp = event.timestamp
        switch event.kind {
        case .boundary:
            return reset()
        case .startOfText:
            suffix = ""; atWordBoundary = true
        case .physicalCapsDown:
            guard configuration.hyperEnabled, capsDownAt == nil else { return value }
            capsDownAt = event.timestamp; capsWasChord = false; suffix = ""; previousTap = nil
            value.consume = true
        case .physicalCapsUp:
            guard let down = capsDownAt else { return value }
            value.consume = true; value.resetModifiers = true
            value.toggleCapsLock = configuration.preserveCapsLockTap && !capsWasChord && event.timestamp - down <= 0.25
            capsDownAt = nil; capsWasChord = false
        case .modifierDown:
            suffix = ""; atWordBoundary = false
            if capsDownAt != nil { capsWasChord = true }
            if let current = modifierDown, current.key != event.keyCode { previousTap = nil }
            modifierDown = (event.keyCode, event.timestamp, !event.hasShortcutModifier)
        case .modifierUp:
            defer { modifierDown = nil }
            guard let down = modifierDown, down.key == event.keyCode, down.clean,
                  event.timestamp - down.at <= 0.25,
                  let binding = configuration.doubleTaps.first(where: { $0.key.rawValue == event.keyCode }) else {
                previousTap = nil; return value
            }
            if let previous = previousTap, previous.key == event.keyCode, down.at - previous.at <= 0.35 {
                value.activation = binding.id; previousTap = nil
            } else { previousTap = (event.keyCode, event.timestamp) }
        case .up:
            if consumedKeys.remove(event.keyCode) != nil { value.consume = true }
            value.addHyper = capsDownAt != nil
        case .down:
            previousTap = nil
            if modifierDown != nil { modifierDown?.clean = false }
            let hyper = capsDownAt != nil
            if hyper { capsWasChord = true; value.addHyper = true }
            if event.isRepeat {
                value.consume = consumedKeys.contains(event.keyCode)
                suffix = ""; atWordBoundary = false; return value
            }
            if let binding = configuration.keys.first(where: { $0.key.rawValue == event.keyCode && $0.requiresHyper == hyper }),
               !event.hasShortcutModifier,
               hyper || binding.key.isFunctionKey || field == .nonEditable {
                consumedKeys.insert(event.keyCode); value.consume = true; value.activation = binding.id
                suffix = ""; atWordBoundary = false; return value
            }
            guard field == .editable, !event.hasShortcutModifier, !hyper, !configuration.expansions.isEmpty else {
                suffix = ""; atWordBoundary = false; return value
            }
            guard event.text.count == 1, let character = event.text.first else {
                suffix = ""; atWordBoundary = false; return value
            }
            if character.isWhitespace {
                value.expansion = configuration.expansions.first(where: { $0.keyword == suffix })
                suffix = ""; atWordBoundary = true
            } else if atWordBoundary || !suffix.isEmpty {
                let candidate = suffix + event.text
                if configuration.expansions.contains(where: { $0.keyword.hasPrefix(candidate) }) {
                    suffix = candidate
                } else { suffix = ""; atWordBoundary = false }
            }
        }
        return value
    }
}
