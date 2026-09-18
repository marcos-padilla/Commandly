import ApplicationServices
import Carbon
import Foundation
import Infrastructure

/// Thread-confined focused-field identity. It reads only role, range and the configured keyword's
/// bounded range; it never reads an entire field, selection contents, window title or application name.
final class KeyboardExpansionFocus {
    let element: AXUIElement
    let field: CompanionKeyboardField
    let caret: Int?
    private init(element: AXUIElement, field: CompanionKeyboardField, caret: Int?) {
        self.element = element; self.field = field; self.caret = caret
    }
    static func capture() -> KeyboardExpansionFocus? {
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.04)
        guard let element = focusedElement(system) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.04)
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        if subrole == kAXSecureTextFieldSubrole {
            return .init(element: element, field: .secure, caret: nil)
        }
        let role = attribute(element, kAXRoleAttribute) as? String
        let editableRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        if let role, editableRoles.contains(role) {
            var textSettable = DarwinBoolean(false); var rangeSettable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &textSettable) == .success,
                  AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &rangeSettable) == .success,
                  textSettable.boolValue, rangeSettable.boolValue,
                  let range = selectedRange(element), range.length == 0 else {
                return .init(element: element, field: .unknown, caret: nil)
            }
            return .init(element: element, field: .editable, caret: range.location)
        }
        let nonEditableRoles = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXStaticTextRole, kAXToolbarRole]
        return .init(element: element, field: role.map(nonEditableRoles.contains) == true ? .nonEditable : .unknown, caret: nil)
    }
    static func same(_ lhs: KeyboardExpansionFocus?, _ rhs: KeyboardExpansionFocus?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let lhs, let rhs else { return false }
        return lhs.field == rhs.field && CFEqual(lhs.element, rhs.element)
    }
    func replaceSuffix(_ expansion: CompanionKeywordExpansion, authorized: @Sendable () -> Bool) {
        guard authorized(), field == .editable, let caret, caret >= expansion.keyword.utf16.count,
              Self.same(self, Self.capture()), let original = Self.selectedRange(element),
              original.location == caret, original.length == 0 else { return }
        let length = expansion.keyword.utf16.count
        var range = CFRange(location: caret - length, length: length)
        guard Self.string(element, range: range) == expansion.keyword else { return }
        if range.location > 0 {
            guard let preceding = Self.string(element, range: CFRange(location: range.location - 1, length: 1)),
                  preceding.first?.isWhitespace == true else { return }
        }
        guard authorized(), !IsSecureEventInputEnabled(), Self.same(self, Self.capture()),
              Self.sameRange(Self.selectedRange(element), original),
              let value = AXValueCreate(.cfRange, &range),
              authorized(), AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return }
        guard authorized(), !IsSecureEventInputEnabled(), Self.same(self, Self.captureForReplacement()),
              Self.sameRange(Self.selectedRange(element), range), Self.string(element, range: range) == expansion.keyword,
              AXIsProcessTrusted(), !IsSecureEventInputEnabled(), authorized() else {
            restoreCaret(original, onlyIfSelected: range, authorized: authorized); return
        }
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, expansion.replacement as CFString) != .success {
            restoreCaret(original, onlyIfSelected: range, authorized: authorized)
        }
    }
    // After selecting the exact suffix, the field no longer has a zero-length range. Identity and
    // secure-role validation remain mandatory without treating our selected suffix as a focus change.
    private static func captureForReplacement() -> KeyboardExpansionFocus? {
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.04)
        guard let element = focusedElement(system),
              attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return nil }
        return .init(element: element, field: .editable, caret: nil)
    }
    private func restoreCaret(_ original: CFRange, onlyIfSelected range: CFRange, authorized: @Sendable () -> Bool) {
        guard Self.same(self, Self.captureForReplacement()), Self.sameRange(Self.selectedRange(element), range) else { return }
        var original = original
        if let value = AXValueCreate(.cfRange, &original), AXIsProcessTrusted(), !IsSecureEventInputEnabled(), authorized() {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }
    private static func sameRange(_ lhs: CFRange?, _ rhs: CFRange) -> Bool {
        lhs?.location == rhs.location && lhs?.length == rhs.length
    }
    private static func focusedElement(_ system: AXUIElement) -> AXUIElement? {
        guard let value = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        let typed = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(typed) == .cfRange, AXValueGetValue(typed, .cfRange, &range),
              range.location >= 0, range.location <= 10_000_000, range.length >= 0, range.length <= 32 else { return nil }
        return range
    }
    private static func string(_ element: AXUIElement, range: CFRange) -> String? {
        var range = range
        guard range.length <= 32, let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
              let text = value as? String, text.utf16.count == range.length else { return nil }
        return text
    }
}
