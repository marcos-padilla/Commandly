import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Translate application model", .timeLimit(.minutes(1)))
@MainActor
struct TranslationViewModelTests {
    @Test
    func openingLoadsEntireNativeCatalogAndPreferredTargetWithoutTranslationOrDownloads() async {
        let harness = TranslationTestHarness()
        let model = await harness.loadedModel()
        #expect(model.languages == TranslationTestValue.catalog)
        #expect(model.targetLanguageID == "es" && model.sourceLanguageID == nil)
        #expect(model.pairAvailability == .automaticSource)
        #expect(harness.translator.requests.isEmpty && harness.translator.preparations.isEmpty)
        #expect(await harness.copier.values.isEmpty)
        #expect(await harness.catalog.catalogCalls == 1)
        model.stop()
    }

    @Test
    func wordAndParagraphSubmissionPreserveExactInputAndRequireExplicitCopy() async throws {
        for wordMode in [false, true] {
            let harness = TranslationTestHarness()
            let model = await harness.loadedModel(word: wordMode)
            model.input = " hello "
            #expect(harness.translator.requests.isEmpty)
            model.translate(); await model.waitForWorkForTesting()
            #expect(harness.translator.requests == [try TextTranslationRequest(text: " hello ", sourceLanguageID: nil, targetLanguageID: "es")])
            #expect(model.result == (try TranslationTestValue.result()))
            #expect(await harness.copier.values.isEmpty)
            model.copy(); await model.waitForWorkForTesting()
            #expect(await harness.copier.values == ["hola"])
            model.stop()
        }
    }

    @Test
    func selectedSourceChecksPairAndUnsupportedPairNeverRunsTranslation() async {
        let harness = TranslationTestHarness()
        let model = await harness.loadedModel()
        model.sourceLanguageID = "en"; model.input = "hello"
        await model.waitForCatalogForTesting()
        model.translate(); await model.waitForWorkForTesting()
        #expect(harness.translator.requests.first?.sourceLanguageID == "en")
        model.sourceLanguageID = "es"
        await model.waitForCatalogForTesting()
        #expect(model.pairAvailability == .unsupported && !model.canTranslate)
        model.translate()
        #expect(harness.translator.requests.count == 1 && model.errorMessage != nil)
        model.stop()
    }

    @Test
    func explicitLanguagePreparationNeverSubmitsTheDraft() async {
        let harness = TranslationTestHarness()
        await harness.catalog.configure(pair: .downloadRequired)
        let model = await harness.loadedModel()
        model.sourceLanguageID = "en"; model.input = "private local draft"
        await model.waitForCatalogForTesting()
        #expect(model.canPrepare && harness.translator.preparations.isEmpty)
        model.prepareLanguages(); await model.waitForWorkForTesting()
        #expect(harness.translator.preparations == ["en>es"])
        #expect(harness.translator.requests.isEmpty && model.result == nil)
        #expect(model.input == "private local draft")
        model.stop()
    }

    @Test
    func invalidInputAndUnknownLanguageFailBeforeCallingNativeTranslator() async {
        let harness = TranslationTestHarness()
        let model = await harness.loadedModel()
        for text in ["  \n", String(repeating: "a", count: 10_001)] {
            model.input = text; model.translate()
            #expect(model.errorMessage != nil && harness.translator.requests.isEmpty)
        }
        model.input = "hello"; model.targetLanguageID = "not-in-catalog"; model.translate()
        #expect(model.errorMessage != nil && harness.translator.requests.isEmpty)
        model.stop()
    }

    @Test
    func editingCancelsOldRequestAndLateResultCannotReplaceTheNewTranslation() async throws {
        let harness = TranslationTestHarness()
        harness.translator.blocksTranslation = true
        let model = await harness.loadedModel()
        model.input = "old"; model.translate()
        await harness.translator.waitForRequests(1)
        let oldTask = model.pendingWorkForTesting()
        model.input = "current"
        #expect(harness.translator.cancellations == 1 && !model.isBusy && model.result == nil)
        model.translate(); await harness.translator.waitForRequests(2)
        try harness.translator.releaseFirst("stale")
        await oldTask?.value
        #expect(model.result == nil && model.isTranslating)
        try harness.translator.releaseFirst("current result")
        await model.waitForWorkForTesting()
        #expect(model.result?.text == "current result")
        model.stop()
    }

    @Test
    func escapeCancelsLocalRequestKeepsDraftAndStopClearsText() async throws {
        let harness = TranslationTestHarness()
        harness.translator.blocksTranslation = true
        let model = await harness.loadedModel()
        model.input = "draft"; model.translate()
        await harness.translator.waitForRequests(1)
        let task = model.pendingWorkForTesting()
        #expect(model.handleEscape())
        #expect(model.input == "draft" && !model.isBusy && model.statusMessage?.contains("downloads may continue") == true)
        try harness.translator.releaseFirst("late")
        await task?.value
        #expect(model.result == nil && !model.handleEscape())
        model.stop()
        #expect(model.input.isEmpty && model.result == nil)
    }

    @Test
    func detectionFailureAllowsChosenSourceRetryAndCopyFailurePreservesReview() async {
        let harness = TranslationTestHarness()
        let model = await harness.loadedModel(word: true)
        harness.translator.failure = .unableToDetectSource
        model.input = "gift"; model.translate(); await model.waitForWorkForTesting()
        #expect(model.input == "gift" && model.errorMessage?.contains("Choose it explicitly") == true)
        model.sourceLanguageID = "en"; await model.waitForCatalogForTesting()
        harness.translator.failure = nil
        model.translate(); await model.waitForWorkForTesting()
        await harness.copier.setFailure(true)
        model.copy(); await model.waitForWorkForTesting()
        #expect(model.result?.text == "hola" && model.errorMessage?.contains("could not be copied") == true)
        await harness.copier.setFailure(false)
        model.copy(); await model.waitForWorkForTesting()
        #expect(await harness.copier.values == ["hola"])
        model.stop()
    }

    @Test
    func refreshFailureIsRecoverableAndSwapNeverTranslates() async {
        let harness = TranslationTestHarness()
        await harness.catalog.configure(failure: .unavailable)
        let model = await harness.loadedModel()
        #expect(model.languages.isEmpty && !model.isLoadingLanguages && model.errorMessage != nil)
        await harness.catalog.configure()
        model.loadLanguages(); await model.waitForCatalogForTesting()
        model.sourceLanguageID = "en"; model.swapLanguages()
        await model.waitForCatalogForTesting()
        #expect(model.sourceLanguageID == "es" && model.targetLanguageID == "en")
        #expect(harness.translator.requests.isEmpty && harness.translator.preparations.isEmpty)
        model.stop()
    }

    @Test
    func preferredTargetMatchesCanonicalRegionAndScriptBeforeBaseLanguage() async {
        let catalog = [TranslationLanguage(id: "pt-BR", name: "Portuguese (Brazil)"),
                       TranslationLanguage(id: "pt-PT", name: "Portuguese (Portugal)"),
                       TranslationLanguage(id: "zh-Hans", name: "Chinese (Simplified)"),
                       TranslationLanguage(id: "zh-Hant", name: "Chinese (Traditional)")]
        for (preference, expected) in [("pt-PT", "pt-PT"), ("pt-BR", "pt-BR"), ("zh-Hant", "zh-Hant"),
                                       ("zh-Hans", "zh-Hans"), ("zh-Hant-HK", "zh-Hant")] {
            let harness = TranslationTestHarness()
            await harness.catalog.configure(catalog: catalog)
            let services = TranslationApplicationServices(languages: harness.catalog, translator: harness.translator,
                copier: harness.copier, preferredLanguages: [preference])
            let model = TranslationViewModel(services: services, onGoBack: {})
            model.loadLanguages(); await model.waitForCatalogForTesting()
            #expect(model.targetLanguageID == expected)
            #expect(harness.translator.requests.isEmpty && harness.translator.preparations.isEmpty)
            model.stop()
        }
    }

    @Test
    func refreshingLanguageCatalogPreservesAnExplicitTargetChoice() async {
        let harness = TranslationTestHarness()
        let model = await harness.loadedModel()
        #expect(model.targetLanguageID == "es")
        model.targetLanguageID = "zh-Hant"
        model.loadLanguages(); await model.waitForCatalogForTesting()
        #expect(model.targetLanguageID == "zh-Hant")
        model.stop()
    }

    @Test
    func olderPairAvailabilityCannotOverwriteTheNewSelection() async {
        let catalog = TranslationGatedCatalog()
        let harness = TranslationTestHarness()
        let services = TranslationApplicationServices(languages: catalog, translator: harness.translator, copier: harness.copier, preferredLanguages: ["es"])
        let model = TranslationViewModel(services: services, onGoBack: {})
        model.loadLanguages(); await model.waitForCatalogForTesting()
        model.sourceLanguageID = "en"
        await catalog.waitForPair("en>es")
        let old = model.pendingAvailabilityForTesting()
        model.sourceLanguageID = "zh-Hant"
        await catalog.waitForPair("zh-Hant>es")
        await catalog.complete("zh-Hant>es", with: .installed)
        await model.waitForCatalogForTesting()
        await catalog.complete("en>es", with: .unsupported)
        await old?.value
        #expect(model.sourceLanguageID == "zh-Hant" && model.pairAvailability == .installed)
        model.stop()
    }
}

private actor TranslationGatedCatalog: TranslationLanguageProviding {
    private var pending: [String: CheckedContinuation<TranslationPairAvailability, Never>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func supportedLanguages() async throws -> [TranslationLanguage] { TranslationTestValue.catalog }
    func availability(sourceLanguageID: String, targetLanguageID: String) async throws -> TranslationPairAvailability {
        let key = "\(sourceLanguageID)>\(targetLanguageID)"
        return await withCheckedContinuation { continuation in
            pending[key] = continuation
            waiters.removeValue(forKey: key)?.resume()
        }
    }
    func waitForPair(_ key: String) async {
        if pending[key] != nil { return }
        await withCheckedContinuation { waiters[key] = $0 }
    }
    func complete(_ key: String, with value: TranslationPairAvailability) { pending.removeValue(forKey: key)?.resume(returning: value) }
}
