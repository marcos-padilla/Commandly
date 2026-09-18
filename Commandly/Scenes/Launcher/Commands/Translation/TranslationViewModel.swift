import CommandKit
import Foundation
import Infrastructure
import Observation

enum TranslationActionID {
    static let translate = CommandActionID(rawValue: "translate.submit")
    static let prepare = CommandActionID(rawValue: "translate.prepare-languages")
    static let copy = CommandActionID(rawValue: "translate.copy")
    static let clear = CommandActionID(rawValue: "translate.clear")
    static let cancel = CommandActionID(rawValue: "translate.cancel")
    static let refresh = CommandActionID(rawValue: "translate.refresh-languages")
    static let swap = CommandActionID(rawValue: "translate.swap-languages")
}

@MainActor
@Observable
final class TranslationViewModel: LauncherApplicationModel {
    @ObservationIgnored private let services: TranslationApplicationServices
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var catalogWork: Task<Void, Never>?
    @ObservationIgnored private var availabilityWork: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var catalogGeneration = 0
    @ObservationIgnored private var availabilityGeneration = 0
    let isWordMode: Bool
    var input = "" { didSet { if input != oldValue { draftChanged() } } }
    var sourceLanguageID: String? { didSet { if sourceLanguageID != oldValue { draftChanged(); refreshAvailability() } } }
    var targetLanguageID = "" { didSet { if targetLanguageID != oldValue { draftChanged(); refreshAvailability() } } }
    var showsActionsMenu = false
    private(set) var languages: [TranslationLanguage] = []
    private(set) var result: TextTranslationResult?
    private(set) var pairAvailability: TranslationPairAvailability = .automaticSource
    private(set) var isLoadingLanguages = false
    private(set) var isTranslating = false
    private(set) var isPreparing = false
    private(set) var isCopying = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String? = "Choose a target language and enter text to translate."

    init(services: TranslationApplicationServices, isWordMode: Bool = false, onGoBack: @escaping () -> Void) {
        self.services = services; self.isWordMode = isWordMode; self.onGoBack = onGoBack
    }
    deinit { work?.cancel(); catalogWork?.cancel(); availabilityWork?.cancel() }

    var isBusy: Bool { isTranslating || isPreparing || isCopying }
    var canTranslate: Bool {
        !isBusy && !isLoadingLanguages && targetLanguageID.isEmpty == false && pairAvailability != .unsupported
        && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    var canPrepare: Bool { !isBusy && sourceLanguageID != nil && targetLanguageID.isEmpty == false && pairAvailability == .downloadRequired }
    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if isTranslating || isPreparing { primary = .init(id: TranslationActionID.cancel, title: "Cancel", isPrimary: true, keyHint: .escape) }
        else { primary = .init(id: TranslationActionID.translate, title: "Translate", isPrimary: true,
                              keyHint: isWordMode ? .return : CommandKeyHint(symbols: ["⌘", "↩"]), isEnabled: canTranslate) }
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: TranslationActionID.translate, title: "Translate", isEnabled: canTranslate),
         .init(id: TranslationActionID.prepare, title: "Download Languages…", isEnabled: canPrepare),
         .init(id: TranslationActionID.copy, title: "Copy Translation", isEnabled: result != nil && !isBusy),
         .init(id: TranslationActionID.swap, title: "Swap Languages", isEnabled: sourceLanguageID != nil && !isBusy),
         .init(id: TranslationActionID.clear, title: "Clear Text"),
         .init(id: TranslationActionID.refresh, title: "Refresh Languages", isEnabled: !isLoadingLanguages),
         .init(id: TranslationActionID.cancel, title: "Cancel Translation", isEnabled: isTranslating || isPreparing)]
    }

    /// Reads support metadata; never constructs a translation session or requests a download.
    func loadLanguages() {
        catalogGeneration += 1
        let id = catalogGeneration
        catalogWork?.cancel()
        isLoadingLanguages = true
        errorMessage = nil
        catalogWork = Task { [weak self, services] in
            do {
                let catalog = try await services.languages.supportedLanguages()
                try Task.checkCancellation()
                guard let self, catalogGeneration == id else { return }
                guard !catalog.isEmpty, catalog.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else { throw TextTranslationError.unavailable }
                languages = catalog
                if catalog.contains(where: { $0.id == targetLanguageID }) == false {
                    targetLanguageID = preferredTarget(in: catalog)
                }
                if let sourceLanguageID, !catalog.contains(where: { $0.id == sourceLanguageID }) { self.sourceLanguageID = nil }
                isLoadingLanguages = false
                refreshAvailability()
            } catch {
                guard let self, catalogGeneration == id else { return }
                isLoadingLanguages = false
                if error is CancellationError { return }
                fail(error as? TextTranslationError ?? .unavailable)
            }
        }
    }

    func translate() {
        guard !isBusy else { return }
        do {
            guard languages.contains(where: { $0.id == targetLanguageID }),
                  sourceLanguageID.map({ id in languages.contains(where: { $0.id == id }) }) ?? true else { throw TextTranslationError.unsupportedLanguage }
            guard pairAvailability != .unsupported else { throw TextTranslationError.unsupportedPair }
            let request = try TextTranslationRequest(text: input, sourceLanguageID: sourceLanguageID, targetLanguageID: targetLanguageID)
            cancelWork()
            let id = generation
            result = nil; errorMessage = nil; isTranslating = true
            statusMessage = sourceLanguageID == nil ? "Detecting and translating. Apple may ask you to choose the source language or download models…" : "Translating. Apple may ask to download language models…"
            work = Task { [weak self, services] in
                do {
                    let translated = try await services.translator.translate(request)
                    try Task.checkCancellation()
                    guard let self, generation == id else { return }
                    result = translated; isTranslating = false
                    statusMessage = "Translation ready. Review it before copying."
                } catch { self?.completeFailure(error, generation: id) }
            }
        } catch { fail(error as? TextTranslationError ?? .translationFailed) }
    }

    func prepareLanguages() {
        guard canPrepare, let source = sourceLanguageID else { return }
        cancelWork()
        let id = generation, target = targetLanguageID
        isPreparing = true; errorMessage = nil
        statusMessage = "Review Apple’s language download prompt."
        work = Task { [weak self, services] in
            do {
                try await services.translator.prepare(sourceLanguageID: source, targetLanguageID: target)
                try Task.checkCancellation()
                guard let self, generation == id else { return }
                isPreparing = false
                statusMessage = "Language preparation requested. Translate when the languages are ready."
                refreshAvailability()
            } catch { self?.completeFailure(error, generation: id) }
        }
    }

    func copy() {
        guard let result, !isBusy else { return }
        let id = generation
        isCopying = true; errorMessage = nil
        work = Task { [weak self, services] in
            do {
                try Task.checkCancellation()
                try await services.copier.copy(result.text)
                try Task.checkCancellation()
                guard let self, generation == id else { return }
                isCopying = false; statusMessage = "Translation copied."
            } catch { self?.completeFailure(error is CancellationError ? error : TextTranslationError.copyFailed, generation: id) }
        }
    }

    func cancel() { cancelWork(); statusMessage = "Translation cancelled. Apple-managed downloads may continue." }
    func clear() { cancelWork(); input = ""; result = nil; errorMessage = nil; statusMessage = "Text cleared." }
    func swapLanguages() {
        guard !isBusy, let source = sourceLanguageID, !targetLanguageID.isEmpty else { return }
        let target = targetLanguageID
        sourceLanguageID = target; targetLanguageID = source
    }
    func stop() {
        cancelWork()
        catalogGeneration += 1; catalogWork?.cancel(); catalogWork = nil
        availabilityGeneration += 1; availabilityWork?.cancel(); availabilityWork = nil
        isLoadingLanguages = false
        input = ""; result = nil; errorMessage = nil; showsActionsMenu = false
        statusMessage = "Translation text cleared."
    }
    func goBack() { stop(); onGoBack() }
    func moveSelection(offset: Int) { _ = offset }
    func handleEscape() -> Bool { if isTranslating || isPreparing { cancel(); return true }; return false }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case TranslationActionID.translate: translate()
        case TranslationActionID.prepare: prepareLanguages()
        case TranslationActionID.copy: copy()
        case TranslationActionID.clear: clear()
        case TranslationActionID.cancel: cancel()
        case TranslationActionID.refresh: loadLanguages()
        case TranslationActionID.swap: swapLanguages()
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }
    func waitForWorkForTesting() async { await work?.value }
    func waitForCatalogForTesting() async { await catalogWork?.value; await availabilityWork?.value }
    func pendingWorkForTesting() -> Task<Void, Never>? { work }
    func pendingAvailabilityForTesting() -> Task<Void, Never>? { availabilityWork }

    private func draftChanged() {
        cancelWork(); result = nil; errorMessage = nil
        statusMessage = "Choose Translate when the text is ready."
    }
    private func cancelWork() {
        generation += 1; work?.cancel(); work = nil
        if isTranslating || isPreparing { services.translator.cancel() }
        isTranslating = false; isPreparing = false; isCopying = false
    }
    private func refreshAvailability() {
        availabilityGeneration += 1
        let id = availabilityGeneration
        availabilityWork?.cancel()
        guard let source = sourceLanguageID, !targetLanguageID.isEmpty else { pairAvailability = .automaticSource; return }
        let target = targetLanguageID
        pairAvailability = .checking
        availabilityWork = Task { [weak self, services] in
            do {
                let state = try await services.languages.availability(sourceLanguageID: source, targetLanguageID: target)
                try Task.checkCancellation()
                guard let self, availabilityGeneration == id else { return }
                pairAvailability = state
            } catch {
                guard let self, availabilityGeneration == id, !(error is CancellationError) else { return }
                fail(.unavailable)
            }
        }
    }
    private func preferredTarget(in catalog: [TranslationLanguage]) -> String {
        for preference in services.preferredLanguages {
            let wanted = Locale.Language(identifier: preference)
            let candidates = catalog.map { ($0, Locale.Language(identifier: $0.id)) }
            if let exact = candidates.first(where: { $0.1.maximalIdentifier == wanted.maximalIdentifier }) { return exact.0.id }
            if let script = candidates.first(where: { $0.1.languageCode == wanted.languageCode && $0.1.script == wanted.script }) { return script.0.id }
            if let language = candidates.first(where: { $0.1.languageCode == wanted.languageCode }) { return language.0.id }
        }
        return catalog.first?.id ?? ""
    }
    private func completeFailure(_ error: Error, generation id: Int) {
        guard generation == id else { return }
        isTranslating = false; isPreparing = false; isCopying = false
        if error is CancellationError { statusMessage = "Translation cancelled. Apple-managed downloads may continue." }
        else { fail(error as? TextTranslationError ?? .translationFailed) }
    }
    private func fail(_ error: TextTranslationError) {
        statusMessage = nil
        errorMessage = switch error {
        case .emptyInput: "Enter a word or some text to translate."
        case .inputTooLong: "Translate up to 10,000 characters and 64 KiB at a time. Shorten this text and retry."
        case .unsupportedLanguage: "Choose a language from Apple’s supported language list. Refresh Languages if availability changed."
        case .unsupportedPair: "Apple Translation does not support this language pair. Choose different source and target languages."
        case .unableToDetectSource: "The source language is unclear. Choose it explicitly, especially for a single word, then retry."
        case .languagesNotInstalled: "The language models are not ready. Retry to review Apple’s download prompt, or choose a source and Download Languages."
        case .unavailable: "Apple Translation is unavailable right now. Refresh Languages and retry."
        case .invalidResult: "The translation result could not be displayed. Try a shorter passage and retry."
        case .translationFailed: "Translation did not finish. Review any Apple download prompt, then retry. Your text is still here."
        case .copyFailed: "The translation could not be copied. Try Copy Translation again."
        }
    }
}
