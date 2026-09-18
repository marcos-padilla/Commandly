import CommandKit
import Foundation
import Infrastructure
import Observation

enum WritingToolsActionID {
    static let check = CommandActionID(rawValue: "writing.check")
    static let cancel = CommandActionID(rawValue: "writing.cancel")
    static let copy = CommandActionID(rawValue: "writing.copy")
    static let corrections = CommandActionID(rawValue: "writing.corrections")
    static let clear = CommandActionID(rawValue: "writing.clear")
    static let instructions = CommandActionID(rawValue: "writing.inline-help")
}

@Observable
@MainActor
final class WritingToolsViewModel: LauncherApplicationModel {
    var input = "" { didSet { if input != oldValue { invalidateReport() } } }
    var languageID = "" { didSet { if languageID != oldValue { invalidateReport() } } }
    var output = ""
    var showsActionsMenu = false
    var showsInlineInstructions: Bool
    private(set) var report: WritingCheckReport?
    private(set) var isChecking = false
    private(set) var statusMessage: String?
    let languages: [String]
    @ObservationIgnored private let checker: any WritingChecking
    @ObservationIgnored private let pasteboard: any PasteboardAccessing
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var request: (any WritingCheckCancelling)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private var selectedReplacements: [UUID: String] = [:]
    @ObservationIgnored private var generatedOutput = ""

    init(services: WritingToolsApplicationServices, showsInlineInstructions: Bool = false, onGoBack: @escaping () -> Void) {
        checker = services.checker; pasteboard = services.pasteboard; languages = services.checker.availableLanguages
        self.showsInlineInstructions = showsInlineInstructions; self.onGoBack = onGoBack
    }

    var canCheck: Bool {
        isChecking == false && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && input.utf8.count <= WritingCorrectionPolicy.maximumInputBytes
    }
    var canCopy: Bool { isChecking == false && output.isEmpty == false && output.utf8.count <= WritingCorrectionPolicy.maximumOutputBytes }
    var canUseCorrections: Bool { report?.issues.contains { $0.automaticReplacement != nil } == true && isChecking == false }
    var footerActions: [CommandActionDescriptor] {
        let action = isChecking
            ? CommandActionDescriptor(id: WritingToolsActionID.cancel, title: "Cancel Check", isPrimary: true, keyHint: .escape)
            : CommandActionDescriptor(id: WritingToolsActionID.check, title: "Check Text", isPrimary: true, keyHint: .init(symbols: ["⌘", "↩"]), isEnabled: canCheck)
        return [action, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: WritingToolsActionID.copy, title: "Copy Reviewed Text", isEnabled: canCopy),
         .init(id: WritingToolsActionID.corrections, title: "Use Automatic Suggestions", isEnabled: canUseCorrections),
         .init(id: WritingToolsActionID.clear, title: "Clear Text"),
         .init(id: WritingToolsActionID.instructions, title: "Quick Fix in Other Apps")]
    }

    func check() {
        guard canCheck else { return }
        cancelCheck()
        let token = UUID(); generation = token
        let source = input
        report = nil; selectedReplacements = [:]; setGeneratedOutput(""); statusMessage = nil; isChecking = true
        request = checker.check(text: source, language: languageID.isEmpty ? nil : languageID) { [weak self] result in
            guard let self, generation == token, input == source, isChecking else { return }
            isChecking = false; request = nil
            switch result {
            case .success(let report):
                guard report.source == source, report.issues.count <= WritingCorrectionPolicy.maximumIssues,
                      Set(report.issues.map(\.id)).count == report.issues.count,
                      report.issues.allSatisfy({ $0.range.isValid(in: source) }) else {
                    statusMessage = "The checker returned invalid ranges. Try checking this text again."; return
                }
                self.report = report; setGeneratedOutput(source)
                statusMessage = report.isTruncated ? "There are more issues than this review can show. Check a smaller selection."
                    : report.issues.isEmpty ? "No issues were returned by the native checker."
                    : "Review \(report.issues.count) suggestions before copying the result."
            case .failure(let error):
                statusMessage = Self.message(error)
            }
        }
    }

    func useAutomaticSuggestions() {
        guard let report, report.source == input, isChecking == false else { return }
        guard output == generatedOutput else { statusMessage = "Restore Original before replacing your manual edits with automatic suggestions."; return }
        do {
            guard report.isTruncated == false else { throw WritingCheckError.malformedResult }
            var choices = selectedReplacements
            for issue in report.issues where choices[issue.id] == nil {
                if let replacement = issue.automaticReplacement { choices[issue.id] = replacement }
            }
            let result = try WritingCorrectionPolicy.applying(choices, to: report)
            selectedReplacements = choices
            setGeneratedOutput(result)
            statusMessage = "Suggested changes are in the result. Review or edit it before copying."
        } catch { statusMessage = "Some suggestions overlap or need a choice. Edit the result directly or check a smaller selection." }
    }

    func useSuggestion(_ replacement: String, for issue: WritingIssue) {
        guard let report, report.source == input, isChecking == false else { return }
        // Recompute all accepted choices against the immutable original. Never apply shifted
        // native offsets to a manually edited result or discard earlier accepted suggestions.
        guard output == generatedOutput else { statusMessage = "Restore Original before applying suggestions to manually edited text, or keep editing the result directly."; return }
        do {
            var choices = selectedReplacements
            choices[issue.id] = replacement
            let result = try WritingCorrectionPolicy.applying(choices, to: report)
            selectedReplacements = choices
            setGeneratedOutput(result)
            statusMessage = "Applied \(choices.count) suggestions. Continue reviewing or edit the result before copying."
        }
        catch { statusMessage = "This suggestion could not be applied. Edit the result directly." }
    }
    func restoreOriginal() {
        guard report != nil else { return }
        selectedReplacements = [:]; setGeneratedOutput(input)
        statusMessage = "Original text restored in the review result."
    }
    func cancelCheck() {
        generation = UUID(); request?.cancel(); request = nil
        if isChecking { statusMessage = "Check canceled." }
        isChecking = false
    }
    func copyResult() {
        guard canCopy else { return }
        let text = output; let token = generation
        copyTask?.cancel()
        copyTask = Task { @MainActor [weak self, pasteboard] in
            guard Task.isCancelled == false, self?.generation == token else { return }
            await pasteboard.writeString(text)
            guard Task.isCancelled == false, self?.generation == token else { return }
            self?.statusMessage = "Copied the reviewed text."
        }
    }
    func clear() { cancelCheck(); input = ""; selectedReplacements = [:]; setGeneratedOutput(""); report = nil; statusMessage = nil }
    func stop() { cancelCheck(); copyTask?.cancel(); copyTask = nil; clear(); showsActionsMenu = false }
    func goBack() { onGoBack() }
    func moveSelection(offset: Int) {}
    func handleEscape() -> Bool {
        if isChecking { cancelCheck(); return true }
        if showsInlineInstructions { showsInlineInstructions = false; return true }
        return false
    }
    func perform(_ actionID: CommandActionID) {
        showsActionsMenu = false
        switch actionID {
        case WritingToolsActionID.check: check()
        case WritingToolsActionID.cancel: cancelCheck()
        case WritingToolsActionID.copy: copyResult()
        case WritingToolsActionID.corrections: useAutomaticSuggestions()
        case WritingToolsActionID.clear: clear()
        case WritingToolsActionID.instructions: showsInlineInstructions = true
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }
    func waitForCopyForTesting() async { await copyTask?.value }

    private func invalidateReport() { cancelCheck(); report = nil; selectedReplacements = [:]; setGeneratedOutput(""); statusMessage = nil }
    private func setGeneratedOutput(_ text: String) { generatedOutput = text; output = text }
    private static func message(_ error: WritingCheckError) -> String {
        switch error {
        case .emptyInput: "Enter some text before checking."
        case .inputTooLarge: "Check at most 16 KiB of text at a time."
        case .unsupportedLanguage: "This spelling language is not available on your Mac. Choose another language."
        case .cancelled: "Check canceled."
        case .timedOut: "The check took too long. Try a smaller selection."
        default: "The native checker could not finish. Try again or choose another installed language."
        }
    }
}
