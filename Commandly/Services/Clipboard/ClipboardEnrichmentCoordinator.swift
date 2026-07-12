import Foundation

/// Serial capture-time enrichment queue for clipboard history.
///
/// Runs at most one enricher job at a time. Cancelled when entries are deleted or history is cleared.
/// Never logs clipboard or enrichment contents.
@MainActor
final class ClipboardEnrichmentCoordinator {
    private let enricher: any ClipboardContentEnriching
    private var pendingIDs: [UUID] = []
    private var cancelledIDs = Set<UUID>()
    private var inFlightID: UUID?
    private var workerTask: Task<Void, Never>?
    private weak var store: ClipboardHistoryStore?

    init(enricher: any ClipboardContentEnriching) {
        self.enricher = enricher
    }

    func attach(store: ClipboardHistoryStore) {
        self.store = store
    }

    /// Enqueues enrichment for an image/file entry. Text entries are ignored.
    func enqueue(_ entry: ClipboardHistoryEntry) {
        switch entry.contentType {
        case .text:
            return
        case .image, .fileURL:
            break
        }
        cancelledIDs.remove(entry.id)
        if pendingIDs.contains(entry.id) == false, inFlightID != entry.id {
            pendingIDs.append(entry.id)
        }
        pump()
    }

    func cancel(id: UUID) {
        cancelledIDs.insert(id)
        pendingIDs.removeAll { $0 == id }
        if inFlightID == id {
            workerTask?.cancel()
        }
    }

    func cancelAll() {
        let ids = Set(pendingIDs + [inFlightID].compactMap { $0 })
        cancelledIDs.formUnion(ids)
        pendingIDs.removeAll()
        workerTask?.cancel()
        inFlightID = nil
        workerTask = nil
    }

    private func pump() {
        guard workerTask == nil else { return }
        guard let nextID = pendingIDs.first else { return }
        pendingIDs.removeFirst()

        if cancelledIDs.contains(nextID) {
            cancelledIDs.remove(nextID)
            pump()
            return
        }

        guard let store, let entry = store.entry(id: nextID) else {
            pump()
            return
        }

        inFlightID = nextID
        workerTask = Task { [weak self] in
            let enrichment = await self?.enricher.enrich(entry) ?? .skipped()
            await MainActor.run {
                guard let self else { return }
                let id = nextID
                self.inFlightID = nil
                self.workerTask = nil

                if Task.isCancelled || self.cancelledIDs.contains(id) {
                    self.cancelledIDs.remove(id)
                    self.pump()
                    return
                }

                self.store?.applyEnrichment(id: id, enrichment: enrichment)
                self.cancelledIDs.remove(id)
                self.pump()
            }
        }
    }
}
