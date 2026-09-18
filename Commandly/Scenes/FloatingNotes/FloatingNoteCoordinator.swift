import Foundation
import Observation

@MainActor
protocol FloatingNotePresenting: AnyObject {
    var savedRevision: Int { get }
    func newNote()
    func openNote(_ item: ProductivityLibraryItem)
}

/// AppKit is behind this port so multi-window and quit behavior can be tested without real windows.
@MainActor
protocol FloatingNoteWindowPresenting: AnyObject {
    func present(model: FloatingNoteModel, placementIndex: Int, onClosed: @escaping () -> Void)
    func focus()
    func close()
}

/// Retained by the application runtime, independently of the transient launcher session.
@Observable
@MainActor
final class FloatingNoteCoordinator: FloatingNotePresenting {
    private struct Entry {
        let model: FloatingNoteModel
        let window: any FloatingNoteWindowPresenting
    }

    @ObservationIgnored private let persistence: any ProductivityLibraryPersisting
    @ObservationIgnored private let makeWindow: () -> any FloatingNoteWindowPresenting
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var closeQueue: [UUID] = []
    @ObservationIgnored private var closeCompletion: ((Bool) -> Void)?
    private(set) var openWindowCount = 0
    private(set) var savedRevision = 0

    init(
        persistence: any ProductivityLibraryPersisting,
        makeWindow: @escaping () -> any FloatingNoteWindowPresenting = { FloatingNoteWindowController() },
        now: @escaping () -> Date = { Date() }, makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.persistence = persistence
        self.makeWindow = makeWindow
        self.now = now
        self.makeID = makeID
    }

    var hasUnsavedNotes: Bool { entries.values.contains { $0.model.hasUnsavedChanges || $0.model.isSaving } }

    func newNote() { present(item: nil) }

    func openNote(_ item: ProductivityLibraryItem) {
        guard item.kind == .quickNote else { return }
        if let existing = entries.values.first(where: { $0.model.noteID == item.id }) {
            cancelPendingClose()
            existing.window.focus()
            return
        }
        present(item: item)
    }

    /// Used by applicationShouldTerminate. Completion is false if any editor keeps its draft or
    /// cannot save; the caller must reply to AppKit instead of silently terminating.
    func requestCloseAll(onCompletion: @escaping (Bool) -> Void) {
        guard closeCompletion == nil else { return }
        closeQueue = Array(entries.keys).sorted { $0.uuidString < $1.uuidString }
        closeCompletion = onCompletion
        closeNext()
    }

    func modelForTesting(noteID: UUID) -> FloatingNoteModel? {
        entries.values.first(where: { $0.model.noteID == noteID })?.model
    }

    private func present(item: ProductivityLibraryItem?) {
        cancelPendingClose()
        let windowID = makeID()
        // A bad injected identity source cannot replace another live window or discard its draft.
        guard entries[windowID] == nil else { return }
        let noteID = item?.id ?? windowID
        let window = makeWindow()
        let model = FloatingNoteModel(
            noteID: noteID, item: item, persistence: persistence, now: now, makeID: makeID,
            onSaved: { [weak self] in self?.savedRevision += 1 },
            onCloseApproved: { [weak self] in self?.entries[windowID]?.window.close() },
            onCloseCancelled: { [weak self] in self?.cancelPendingClose() }
        )
        entries[windowID] = Entry(model: model, window: window)
        openWindowCount = entries.count
        window.present(model: model, placementIndex: entries.count - 1, onClosed: { [weak self] in self?.didClose(windowID) })
    }

    private func didClose(_ windowID: UUID) {
        entries.removeValue(forKey: windowID)?.model.stop()
        openWindowCount = entries.count
        closeQueue.removeAll { $0 == windowID }
        if closeCompletion != nil { closeNext() }
    }

    private func closeNext() {
        guard let first = closeQueue.first else {
            let completion = closeCompletion
            closeCompletion = nil
            completion?(true)
            return
        }
        guard let entry = entries[first] else {
            closeQueue.removeFirst()
            closeNext()
            return
        }
        entry.window.focus()
        entry.model.requestCloseForTermination()
    }

    private func cancelPendingClose() {
        guard let completion = closeCompletion else { return }
        for id in closeQueue { entries[id]?.model.cancelTerminationCloseRequest() }
        closeCompletion = nil
        closeQueue = []
        completion(false)
    }
}
