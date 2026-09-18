import Foundation
import Infrastructure
@testable import Commandly

nonisolated enum TranslationTestValue {
    static let english = TranslationLanguage(id: "en", name: "English")
    static let spanish = TranslationLanguage(id: "es", name: "Spanish")
    static let catalog = [english, spanish, TranslationLanguage(id: "zh-Hant", name: "Chinese (Traditional)"), TranslationLanguage(id: "pt-BR", name: "Portuguese (Brazil)")]
    static func request(_ text: String = "hello") throws -> TextTranslationRequest {
        try TextTranslationRequest(text: text, sourceLanguageID: nil, targetLanguageID: "es")
    }
    static func result(_ text: String = "hola") throws -> TextTranslationResult {
        try TextTranslationResult(text: text, sourceLanguage: english, targetLanguage: spanish)
    }
}

actor TranslationCatalogFake: TranslationLanguageProviding {
    var catalog = TranslationTestValue.catalog
    var pair: TranslationPairAvailability = .installed
    var failure: TextTranslationError?
    private(set) var catalogCalls = 0
    private(set) var pairs: [String] = []
    func configure(catalog: [TranslationLanguage]? = nil, pair: TranslationPairAvailability? = nil, failure: TextTranslationError? = nil) {
        if let catalog { self.catalog = catalog }; if let pair { self.pair = pair }; self.failure = failure
    }
    func supportedLanguages() async throws -> [TranslationLanguage] {
        catalogCalls += 1; if let failure { throw failure }; return catalog
    }
    func availability(sourceLanguageID: String, targetLanguageID: String) async throws -> TranslationPairAvailability {
        pairs.append("\(sourceLanguageID)>\(targetLanguageID)")
        if let failure { throw failure }; return sourceLanguageID == targetLanguageID ? .unsupported : pair
    }
}

@MainActor final class TextTranslatorFake: TextTranslating {
    private(set) var requests: [TextTranslationRequest] = []
    private(set) var preparations: [String] = []
    private(set) var cancellations = 0
    var failure: TextTranslationError?
    var blocksTranslation = false
    private var translations: [CheckedContinuation<TextTranslationResult, Error>] = []
    private var startedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func translate(_ request: TextTranslationRequest) async throws -> TextTranslationResult {
        requests.append(request)
        for (count, waiter) in startedWaiters where requests.count >= count { waiter.resume() }
        startedWaiters.removeAll { requests.count >= $0.0 }
        if let failure { throw failure }
        if blocksTranslation { return try await withCheckedThrowingContinuation { translations.append($0) } }
        return try TranslationTestValue.result()
    }
    func prepare(sourceLanguageID: String, targetLanguageID: String) async throws {
        preparations.append("\(sourceLanguageID)>\(targetLanguageID)"); if let failure { throw failure }
    }
    func cancel() { cancellations += 1 }
    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { startedWaiters.append((count, $0)) }
    }
    func releaseFirst(_ text: String) throws {
        let result = try TranslationTestValue.result(text)
        if !translations.isEmpty { translations.removeFirst().resume(returning: result) }
    }
}

actor TranslationCopierFake: TranslationResultCopying {
    private(set) var values: [String] = []
    var fails = false
    func setFailure(_ value: Bool) { fails = value }
    func copy(_ text: String) async throws {
        if fails { throw TextTranslationError.copyFailed }; values.append(text)
    }
}

@MainActor struct TranslationTestHarness {
    let catalog = TranslationCatalogFake()
    let translator = TextTranslatorFake()
    let copier = TranslationCopierFake()
    func services() -> TranslationApplicationServices {
        TranslationApplicationServices(languages: catalog, translator: translator, copier: copier, preferredLanguages: ["es-MX"])
    }
    func loadedModel(word: Bool = false) async -> TranslationViewModel {
        let model = TranslationViewModel(services: services(), isWordMode: word, onGoBack: {})
        model.loadLanguages(); await model.waitForCatalogForTesting()
        return model
    }
}
