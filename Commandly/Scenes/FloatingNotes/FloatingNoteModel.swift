import Foundation
import Observation

/// One desktop editor. Saved versions are optimistic concurrency tokens, never a whole-library copy.
@Observable
@MainActor
final class FloatingNoteModel {
    static let maximumBodyBytes = 1_048_576
    static let maximumTitleCharacters = 200

    @ObservationIgnored private let persistence: any ProductivityLibraryPersisting
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private let onSaved: () -> Void
    @ObservationIgnored private let onCloseApproved: () -> Void
    @ObservationIgnored private let onCloseCancelled: () -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    private var savedVersion: ProductivityLibraryItem?
    private enum CloseReason: Equatable { case user, termination }
    @ObservationIgnored private var closeAfterSave: CloseReason?
    @ObservationIgnored private var closeConfirmationReason: CloseReason?
    @ObservationIgnored private var isClosed = false

    private(set) var noteID: UUID
    var title: String
    var content: String
    var isPinned = true
    var showsCloseConfirmation = false
    private(set) var isSaving = false
    private(set) var hasConflict = false
    private(set) var errorMessage: String?
    private(set) var hasSaved = false

    init(
        noteID: UUID, item: ProductivityLibraryItem? = nil,
        persistence: any ProductivityLibraryPersisting,
        now: @escaping () -> Date = { Date() }, makeID: @escaping () -> UUID = { UUID() },
        onSaved: @escaping () -> Void = {}, onCloseApproved: @escaping () -> Void = {},
        onCloseCancelled: @escaping () -> Void = {}
    ) {
        self.noteID = item?.id ?? noteID
        self.savedVersion = item
        self.title = item?.title ?? ""
        self.content = item?.content ?? ""
        self.hasSaved = item != nil
        self.persistence = persistence
        self.now = now
        self.makeID = makeID
        self.onSaved = onSaved
        self.onCloseApproved = onCloseApproved
        self.onCloseCancelled = onCloseCancelled
    }

    deinit { work?.cancel() }

    var hasUnsavedChanges: Bool {
        if let savedVersion { return title != savedVersion.title || content != savedVersion.content }
        return title.isEmpty == false || content.isEmpty == false
    }

    var windowTitle: String {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Quick Note" : String(label.prefix(Self.maximumTitleCharacters))
    }

    var statusText: String {
        if isSaving { return "Saving…" }
        if hasConflict { return "Another editor saved a different version." }
        if errorMessage != nil { return "Not saved" }
        if hasUnsavedChanges { return "Unsaved changes" }
        return hasSaved ? "Saved in Quick Notes" : "A little space to think"
    }

    func save() { beginSaving(asCopy: false, closeReason: nil) }
    func saveAndClose() { beginSaving(asCopy: false, closeReason: closeConfirmationReason ?? .user) }
    func saveAsCopy() { beginSaving(asCopy: true, closeReason: nil) }

    func requestClose() { requestClose(reason: .user) }
    func requestCloseForTermination() { requestClose(reason: .termination) }

    /// Cancelling a quit clears only its own prompt/deferred close, preserving an explicit close
    /// the user had already requested. The authorized save itself always continues.
    func cancelTerminationCloseRequest() {
        if closeAfterSave == .termination { closeAfterSave = nil }
        if closeConfirmationReason == .termination {
            closeConfirmationReason = nil
            showsCloseConfirmation = false
        }
    }

    private func requestClose(reason: CloseReason) {
        guard isClosed == false else { return }
        if isSaving {
            if closeAfterSave == nil { closeAfterSave = reason }
            return
        }
        if hasUnsavedChanges {
            if showsCloseConfirmation == false { closeConfirmationReason = reason }
            showsCloseConfirmation = true
        } else { approveClose() }
    }

    func keepEditing() {
        showsCloseConfirmation = false
        closeAfterSave = nil
        closeConfirmationReason = nil
        onCloseCancelled()
    }

    func discardAndClose() {
        guard isSaving == false else { return }
        showsCloseConfirmation = false
        approveClose()
    }

    func reportOversizedInput() {
        errorMessage = "Keep this note under 1 MiB. The oversized text wasn’t inserted."
    }

    func stop() {
        isClosed = true
        work?.cancel()
        work = nil
        showsCloseConfirmation = false
    }

    func flushSaveForTesting() async { await work?.value }

    private func beginSaving(asCopy: Bool, closeReason: CloseReason?) {
        guard isClosed == false, isSaving == false else { return }
        showsCloseConfirmation = false
        closeConfirmationReason = nil
        if hasUnsavedChanges == false, asCopy == false, hasSaved {
            if closeReason != nil { approveClose() }
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            rejectSave("Write a note before saving.", wasClosing: closeReason != nil)
            return
        }
        guard content.utf8.count <= Self.maximumBodyBytes,
              trimmedTitle.count <= Self.maximumTitleCharacters else {
            rejectSave("Use a title of at most 200 characters and a note under 1 MiB.", wasClosing: closeReason != nil)
            return
        }
        let sourceTitle = title
        let savedTitle = trimmedTitle.isEmpty
            ? String(content.split(whereSeparator: \.isNewline).first?.prefix(80) ?? "Quick Note")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmedTitle
        let timestamp = now()
        let identifier = asCopy ? makeID() : noteID
        let item = ProductivityLibraryItem(
            id: identifier, kind: .quickNote, title: savedTitle.isEmpty ? "Quick Note" : savedTitle,
            content: content, createdAt: asCopy ? timestamp : savedVersion?.createdAt ?? timestamp,
            updatedAt: timestamp, tags: savedVersion?.tags ?? []
        )
        let mutation: ProductivityLibraryMutation = if let savedVersion, asCopy == false {
            .replace(item, expected: savedVersion)
        } else { .create(item) }
        isSaving = true
        hasConflict = false
        errorMessage = nil
        closeAfterSave = closeReason
        work = Task { [weak self, persistence] in
            do {
                _ = try await persistence.applyChanges([mutation])
                try Task.checkCancellation()
                guard let self, isClosed == false else { return }
                savedVersion = item
                noteID = identifier
                if title == sourceTitle { title = item.title }
                hasSaved = true
                isSaving = false
                onSaved()
                if let reason = closeAfterSave {
                    closeAfterSave = nil
                    requestClose(reason: reason)
                }
            } catch {
                guard let self, isClosed == false else { return }
                isSaving = false
                hasConflict = error as? ProductivityLibraryPersistenceError == .conflict
                errorMessage = hasConflict
                    ? "Your draft is intact. Save as Copy keeps it alongside the saved version."
                    : "Your note couldn’t be saved. Keep this window open and try again."
                if closeAfterSave != nil { closeAfterSave = nil; onCloseCancelled() }
            }
        }
    }

    private func rejectSave(_ message: String, wasClosing: Bool) {
        errorMessage = message
        if wasClosing { onCloseCancelled() }
    }

    private func approveClose() {
        isClosed = true
        onCloseApproved()
    }
}
