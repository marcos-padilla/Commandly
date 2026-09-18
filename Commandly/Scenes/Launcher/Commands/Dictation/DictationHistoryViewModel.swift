import Foundation
import Infrastructure
import Observation

@MainActor @Observable
final class DictationHistoryViewModel {
    var query = ""
    var selectedID: UUID?
    var showsDeleteConfirmation = false
    var showsClearConfirmation = false
    private(set) var entries: [DictationHistoryEntry] = []
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    @ObservationIgnored private let store: any DictationHistoryStoring
    @ObservationIgnored private let pasteboard: any PasteboardAccessing
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var copyWork: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    init(store: any DictationHistoryStoring, pasteboard: any PasteboardAccessing) { self.store = store; self.pasteboard = pasteboard }
    deinit { work?.cancel(); copyWork?.cancel() }
    var filtered: [DictationHistoryEntry] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? entries : entries.filter { $0.text.localizedCaseInsensitiveContains(value) || $0.languageName.localizedCaseInsensitiveContains(value) }
    }
    var selected: DictationHistoryEntry? { filtered.first { $0.id == selectedID } ?? filtered.first }
    func load() { run { try await $0.load() } }
    func deleteSelected() {
        guard let id = selected?.id else { return }
        showsDeleteConfirmation = false; run { try await $0.delete(id: id) }
    }
    func clear() { showsClearConfirmation = false; run { try await $0.clear(); return [] } }
    private func run(_ operation: @escaping @Sendable (any DictationHistoryStoring) async throws -> [DictationHistoryEntry]) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; statusMessage = nil; let id = generation
        work = Task { [weak self, store] in
            do {
                let values = try await operation(store); try Task.checkCancellation()
                guard let self, self.generation == id else { return }
                self.entries = values; self.isBusy = false
                if !values.contains(where: { $0.id == self.selectedID }) { self.selectedID = values.first?.id }
            } catch {
                guard let self, !Task.isCancelled, self.generation == id else { return }
                self.isBusy = false; self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.historyUnavailable.errorDescription
            }
        }
    }
    func copySelected() {
        guard let text = selected?.text, !isBusy else { return }
        copyWork?.cancel()
        copyWork = Task { [weak self, pasteboard] in
            guard !Task.isCancelled else { return }; await pasteboard.writeString(text)
            guard let self, !Task.isCancelled else { return }; self.statusMessage = "Saved dictation copied."
        }
    }
    func moveSelection(offset: Int) {
        let values = filtered; guard !values.isEmpty else { return }
        let current = values.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = values[min(max(current + offset, 0), values.count - 1)].id
    }
    func stop() { generation = UUID(); work?.cancel(); copyWork?.cancel(); isBusy = false; entries = []; query = ""; selectedID = nil; showsDeleteConfirmation = false; showsClearConfirmation = false; errorMessage = nil; statusMessage = nil }
    func waitForWorkForTesting() async { await work?.value; await copyWork?.value }
}
