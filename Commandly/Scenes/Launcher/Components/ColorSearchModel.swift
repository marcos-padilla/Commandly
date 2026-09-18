import CommandKit
import Foundation
import Infrastructure
import Observation

nonisolated struct ColorSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let color: CommandlyColor
}

/// Each query creates a new result identity. Old cards, copy tasks and open menus cannot act
/// on a later query, even when that later query contains exactly the same color literal.
@Observable @MainActor
final class ColorSearchModel {
    private let provider: ColorSearchProvider
    private let pasteboard: any PasteboardAccessing
    private var generation = 0
    private(set) var result: ColorSearchResult?
    var selectedFormat: CommandlyColorFormat = .hex
    var showsActions = false
    var actionsQuery = ""
    private(set) var statusMessage: String?
    @ObservationIgnored private var copyTask: Task<Void, Never>?

    init(pasteboard: any PasteboardAccessing, provider: ColorSearchProvider = ColorSearchProvider()) {
        self.pasteboard = pasteboard
        self.provider = provider
    }

    func update(query: String) {
        stop()
        if let color = provider.color(for: query) {
            result = ColorSearchResult(id: "color:\(generation)", color: color)
            selectedFormat = color.defaultFormat
        }
    }

    func stop() {
        generation &+= 1
        copyTask?.cancel()
        copyTask = nil
        result = nil
        statusMessage = nil
        dismissActions()
    }

    func presentActions(resultID: String) {
        guard result?.id == resultID else { return }
        actionsQuery = ""
        showsActions = true
    }

    func dismissActions() {
        showsActions = false
        actionsQuery = ""
    }

    var actions: [CommandActionDescriptor] {
        CommandlyColorFormat.allCases.map { $0.copyAction(isEnabled: result != nil) }
    }

    func perform(_ actionID: CommandActionID, resultID: String) {
        guard let format = CommandlyColorFormat.matching(actionID), result?.id == resultID else { return }
        selectedFormat = format
        copy(resultID: resultID)
    }

    func copy(resultID: String) {
        guard let result, result.id == resultID else { return }
        let format = selectedFormat
        let text = result.color.formatted(format)
        copyTask?.cancel()
        copyTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.result?.id == resultID else { return }
            // An explicit copy already dispatched to the clipboard cannot be revoked. Cancellation
            // prevents a queued write and suppresses stale completion, never claims to undo a write.
            await pasteboard.writeString(text)
            guard !Task.isCancelled, self.result?.id == resultID else { return }
            statusMessage = "\(format.title) copied."
            dismissActions()
        }
    }

    func copyAndWait(resultID: String) async {
        copy(resultID: resultID)
        await copyTask?.value
    }

    func pendingCopyForTesting() -> Task<Void, Never>? { copyTask }

    func flushCopyForTesting() async { await copyTask?.value }
}
