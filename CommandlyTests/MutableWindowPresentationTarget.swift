@testable import Commandly

/// A main-actor-owned target that providers can capture without sharing a mutable local variable.
@MainActor
final class MutableWindowPresentationTarget {
    var value: WindowPresentationTarget

    init(_ value: WindowPresentationTarget) {
        self.value = value
    }
}
