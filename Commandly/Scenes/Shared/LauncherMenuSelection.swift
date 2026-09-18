import Foundation
import Observation
import SwiftUI

/// Stable keyboard selection over the currently visible, enabled menu items.
/// Callers omit unavailable rows, so Return can never activate a disabled or filtered-out item.
nonisolated struct LauncherMenuSelection<ID: Hashable> {
    private(set) var selectedID: ID?

    mutating func reconcile(with enabledIDs: [ID], preferredID: ID? = nil) {
        if let selectedID, enabledIDs.contains(selectedID) { return }
        if let preferredID, enabledIDs.contains(preferredID) {
            selectedID = preferredID
        } else {
            selectedID = enabledIDs.first
        }
    }

    mutating func select(_ id: ID, in enabledIDs: [ID]) {
        guard enabledIDs.contains(id) else { return }
        selectedID = id
    }

    mutating func move(by direction: Int, in enabledIDs: [ID]) {
        guard enabledIDs.isEmpty == false else {
            selectedID = nil
            return
        }
        guard let selectedID, let index = enabledIDs.firstIndex(of: selectedID) else {
            self.selectedID = direction < 0 ? enabledIDs.last : enabledIDs.first
            return
        }
        let offset = direction < 0 ? -1 : direction > 0 ? 1 : 0
        self.selectedID = enabledIDs[(index + offset + enabledIDs.count) % enabledIDs.count]
    }

    func activationID(in enabledIDs: [ID]) -> ID? {
        guard let selectedID, enabledIDs.contains(selectedID) else { return nil }
        return selectedID
    }
}

/// Gives the launcher shell first refusal of Escape while a feature filter is expanded.
/// Ownership is per launcher instance; a disappearing older menu cannot unregister a newer one.
@MainActor
@Observable
final class LauncherTransientMenuState {
    private var ownerID: UUID?
    private var onDismiss: ((Bool) -> Void)?

    func present(id: UUID, onDismiss: @escaping (_ restoringFocus: Bool) -> Void) {
        if ownerID != id {
            _ = dismiss(restoringFocus: false)
        }
        ownerID = id
        self.onDismiss = onDismiss
    }

    func remove(id: UUID) {
        guard ownerID == id else { return }
        ownerID = nil
        onDismiss = nil
    }

    @discardableResult
    func dismiss(restoringFocus: Bool = true) -> Bool {
        guard let onDismiss else { return false }
        ownerID = nil
        self.onDismiss = nil
        onDismiss(restoringFocus)
        return true
    }
}

extension EnvironmentValues {
    @Entry var launcherTransientMenuState: LauncherTransientMenuState?
}
