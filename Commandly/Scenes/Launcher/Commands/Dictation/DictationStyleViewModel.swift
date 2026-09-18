import Foundation
import Infrastructure
import Observation

@MainActor @Observable
final class DictationStyleViewModel {
    var style: DictationWritingStyle = .clean { didSet { if style != oldValue { invalidate() } } }
    var providerID = "" { didSet { if providerID != oldValue { invalidate() } } }
    var proposedText = ""
    private(set) var choices: [QuickAISelection] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var originalText: String?
    @ObservationIgnored private let service: any DictationStyleRewriting
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var loading: Task<Void, Never>?
    init(service: any DictationStyleRewriting) { self.service = service }
    deinit { work?.cancel(); loading?.cancel() }
    var provider: QuickAISelection? { choices.first { $0.id == providerID } }
    func canRewrite(_ text: String) -> Bool { !isWorking && !isLoading && provider?.supportsStreaming == true && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 8 * 1_024 }
    func load() {
        guard !isLoading else { return }
        isLoading = true; invalidate()
        loading = Task { [weak self, service] in
            do {
                let catalog = try await service.selections(); try Task.checkCancellation()
                guard let self else { return }
                self.choices = catalog.selections
                if !self.choices.contains(where: { $0.id == self.providerID }) { self.providerID = self.choices.first { $0.id == catalog.preferredID }?.id ?? self.choices.first?.id ?? "" }
                self.isLoading = false
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.choices = []; self.isLoading = false; self.errorMessage = DictationError.rewriteUnavailable.errorDescription
            }
        }
    }
    func rewrite(_ text: String) {
        guard canRewrite(text), let provider else { return }
        invalidate(); isWorking = true; let id = generation; let style = style
        work = Task { [weak self, service] in
            do {
                let result = try await service.rewrite(text, style: style, selection: provider); try Task.checkCancellation()
                guard let self, self.generation == id else { return }
                self.originalText = text; self.proposedText = result; self.isWorking = false
            } catch {
                guard let self, !Task.isCancelled, self.generation == id else { return }
                self.isWorking = false; self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.rewriteUnavailable.errorDescription
            }
        }
    }
    func result(for currentText: String) -> String? {
        guard originalText == currentText, !proposedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              proposedText.utf8.count <= 64 * 1_024 else { return nil }
        return proposedText
    }
    func invalidate() { generation = UUID(); work?.cancel(); work = nil; isWorking = false; proposedText = ""; originalText = nil; errorMessage = nil }
    func stop() { loading?.cancel(); isLoading = false; invalidate() }
    func waitForLoadingForTesting() async { await loading?.value }
    func waitForRewriteForTesting() async { await work?.value }
    var pendingRewriteForTesting: Task<Void, Never>? { work }
}
