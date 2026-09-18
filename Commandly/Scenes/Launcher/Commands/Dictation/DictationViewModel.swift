import CommandKit
import Foundation
import Infrastructure
import Observation

nonisolated enum DictationPhase { case idle, preparing, recording, stopping }
enum DictationActionID {
    static let start = CommandActionID(rawValue: "dictation.start")
    static let finish = CommandActionID(rawValue: "dictation.finish")
    static let cancel = CommandActionID(rawValue: "dictation.cancel")
    static let save = CommandActionID(rawValue: "dictation.save-history")
    static let history = CommandActionID(rawValue: "dictation.history")
    static let settings = CommandActionID(rawValue: "dictation.microphone-settings")
}

@MainActor @Observable
final class DictationViewModel: LauncherApplicationModel {
    var languageID = "" { didSet { if oldValue != languageID { checkAvailability() } } }
    var microphoneID: String?
    var reviewText = "" { didSet { if reviewText != oldValue { styles.invalidate() } } }
    var showsActionsMenu = false
    var showsHistory = false
    var showsReplaceConfirmation = false
    var showsLeaveConfirmation = false
    private(set) var languages: [DictationLanguage] = []
    private(set) var microphones: [DictationMicrophone] = []
    private(set) var availability: DictationModelAvailability = .unsupported
    private(set) var phase: DictationPhase = .idle
    private(set) var isLoading = false
    private(set) var isCheckingAvailability = false
    private(set) var isDownloading = false
    private(set) var isSaving = false
    private(set) var isCopying = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var startedAt: Date?
    private(set) var microphoneName: String?
    private(set) var hasProvisionalText = false
    private(set) var focusRequest = 0
    let styles: DictationStyleViewModel
    let history: DictationHistoryViewModel
    let fixtureLabel: String?
    @ObservationIgnored private let services: DictationApplicationServices
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private let onAISettings: () -> Void
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var availabilityID = UUID()
    @ObservationIgnored private var currentRequestID: UUID?
    @ObservationIgnored private var draftID = UUID()
    @ObservationIgnored private var draftDate = Date()
    @ObservationIgnored private var durationSeconds = 0.0
    @ObservationIgnored private var savedText: String?
    @ObservationIgnored private var draftLanguage: DictationLanguage?
    @ObservationIgnored private var previousDraft: DraftSnapshot?
    private struct DraftSnapshot { let id: UUID; let date: Date; let text: String; let language: DictationLanguage?; let duration: Double; let savedText: String?; let provisional: Bool }
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var availabilityWork: Task<Void, Never>?
    @ObservationIgnored private var stopWork: Task<Void, Never>?
    @ObservationIgnored private var downloadWork: Task<Void, Never>?
    @ObservationIgnored private var saveWork: Task<Void, Never>?
    @ObservationIgnored private var copyWork: Task<Void, Never>?

    init(services: DictationApplicationServices, onGoBack: @escaping () -> Void, onAISettings: @escaping () -> Void) {
        self.services = services; self.onGoBack = onGoBack; self.onAISettings = onAISettings; fixtureLabel = services.fixtureLabel
        styles = DictationStyleViewModel(service: services.rewriter)
        history = DictationHistoryViewModel(store: services.history, pasteboard: services.pasteboard)
    }
    deinit { work?.cancel(); loading?.cancel(); availabilityWork?.cancel(); stopWork?.cancel(); downloadWork?.cancel(); saveWork?.cancel(); copyWork?.cancel() }
    var language: DictationLanguage? { languages.first { $0.id == languageID } }
    var isBusy: Bool { phase != .idle || isDownloading }
    var canStart: Bool { active && !isBusy && !isLoading && !isCheckingAvailability && !showsHistory && !styles.isWorking && language != nil && availability == .installed }
    var canCopy: Bool { !isBusy && !isCopying && !reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reviewText.utf8.count <= 64 * 1_024 }
    var canSave: Bool { canCopy && !isSaving && reviewText != savedText && (draftLanguage ?? language) != nil }
    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if showsHistory { primary = .init(id: BuiltInCommandActionID.copy, title: "Copy Saved Dictation", isPrimary: true, keyHint: .return, isEnabled: history.selected != nil && !history.isBusy) }
        else if phase == .recording { primary = .init(id: DictationActionID.finish, title: "Stop & Review", isPrimary: true, keyHint: CommandKeyHint(symbols: ["⌘", "↩"])) }
        else if isBusy { primary = .init(id: DictationActionID.start, title: phase == .stopping ? "Stopping…" : "Preparing…", isPrimary: true, isEnabled: false) }
        else { primary = .init(id: BuiltInCommandActionID.copy, title: "Copy Text", isPrimary: true, keyHint: CommandKeyHint(symbols: ["⌘", "⇧", "C"]), isEnabled: canCopy) }
        return [primary, .init(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: DictationActionID.start, title: "Start Dictation", isEnabled: canStart),
         .init(id: DictationActionID.finish, title: "Stop & Review", isEnabled: phase == .recording),
         .init(id: DictationActionID.cancel, title: "Cancel Recording", isEnabled: phase != .idle),
         .init(id: BuiltInCommandActionID.copy, title: "Copy Text", isEnabled: canCopy),
         .init(id: DictationActionID.save, title: "Save to History", isEnabled: canSave),
         .init(id: DictationActionID.history, title: "Saved Dictations", isEnabled: !isBusy),
         .init(id: DictationActionID.settings, title: "Microphone Settings…")]
    }
    func load() {
        guard !active else { return }; active = true; isLoading = true; errorMessage = nil
        let id = generation
        loading = Task { [weak self, services] in
            do {
                async let languages = services.languages.languages()
                async let microphones = services.capture.microphones()
                let values = try await (languages, microphones)
                let preferred = await services.languages.preferredLanguageID(); try Task.checkCancellation()
                guard let self, self.active, self.generation == id else { return }
                self.languages = values.0; self.microphones = values.1; self.isLoading = false
                self.languageID = values.0.first { $0.id == preferred }?.id ?? values.0.first?.id ?? ""
                if self.languageID.isEmpty { self.errorMessage = DictationError.languageUnsupported.errorDescription }
            } catch {
                guard let self, !Task.isCancelled, self.generation == id else { return }
                self.isLoading = false; self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.modelUnavailable.errorDescription
            }
        }
        styles.load()
    }
    func refreshMicrophones() {
        guard !isBusy, !isLoading else { return }
        loading?.cancel(); isLoading = true
        loading = Task { [weak self, capture = services.capture] in
            do {
                let devices = try await capture.microphones(); try Task.checkCancellation()
                guard let self, self.active else { return }
                self.microphones = devices; self.isLoading = false
                if let id = self.microphoneID, !devices.contains(where: { $0.id == id }) { self.microphoneID = nil }
            } catch {
                guard let self, !Task.isCancelled else { return }; self.isLoading = false; self.errorMessage = DictationError.noMicrophone.errorDescription
            }
        }
    }
    func checkAvailability() {
        availabilityID = UUID(); availabilityWork?.cancel(); availability = .unsupported; isCheckingAvailability = false
        guard active, !isBusy, let language else { return }
        let id = availabilityID; isCheckingAvailability = true
        availabilityWork = Task { [weak self, source = services.languages] in
            do {
                let value = try await source.availability(for: language); try Task.checkCancellation()
                guard let self, self.availabilityID == id, self.active else { return }
                self.availability = value; self.isCheckingAvailability = false
            } catch {
                guard let self, !Task.isCancelled, self.availabilityID == id else { return }
                self.isCheckingAvailability = false; self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.modelUnavailable.errorDescription
            }
        }
    }
    func downloadLanguage() {
        guard !isBusy, let language, !isLoading else { return }
        isDownloading = true; errorMessage = nil; let id = generation
        downloadWork = Task { [weak self, source = services.languages] in
            do {
                try await source.download(language: language); try Task.checkCancellation()
                guard let self, self.active, self.generation == id else { return }
                self.isDownloading = false; self.checkAvailability(); self.statusMessage = "Language model is ready. Start Dictation when you are ready."
            } catch {
                guard let self, self.generation == id else { return }
                self.isDownloading = false
                if !Task.isCancelled { self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.downloadFailed.errorDescription }
                self.checkAvailability()
            }
        }
    }
    func cancelDownload() { downloadWork?.cancel(); statusMessage = "Cancelling model download. Apple may retain shared assets." }
    func requestRecording() {
        guard canStart else { return }
        if !reviewText.isEmpty { showsReplaceConfirmation = true } else { beginRecording() }
    }
    func beginRecording() {
        showsReplaceConfirmation = false
        guard canStart, let language else { return }
        let request = DictationCaptureRequest(language: language, microphoneID: microphoneID)
        currentRequestID = request.id; phase = .preparing; errorMessage = nil; statusMessage = nil; styles.invalidate()
        previousDraft = DraftSnapshot(id: draftID, date: draftDate, text: reviewText, language: draftLanguage, duration: durationSeconds, savedText: savedText, provisional: hasProvisionalText)
        work = Task { [weak self, services] in
            await withTaskCancellationHandler {
                do {
                    let permission = await services.microphonePermission.requestAuthorization(); try Task.checkCancellation()
                    switch permission {
                    case .authorized: break
                    case .notDetermined: throw DictationError.permissionRequired
                    case .denied: throw DictationError.permissionDenied
                    case .restricted: throw DictationError.permissionRestricted
                    }
                    let session = try await services.capture.start(request); try Task.checkCancellation()
                    guard self?.active == true, self?.currentRequestID == request.id else { await services.capture.cancel(requestID: request.id); return }
                    self?.captureDidStart(session, language: language)
                    for await event in session.events {
                        guard !Task.isCancelled, let self, self.active, self.currentRequestID == request.id else { break }
                        self.consume(event, id: request.id)
                    }
                    if !Task.isCancelled, self?.currentRequestID == request.id {
                        await services.capture.cancel(requestID: request.id)
                        if self?.currentRequestID == request.id {
                            self?.finishReview(); self?.errorMessage = DictationError.recognitionFailed.errorDescription
                        }
                    }
                } catch {
                    guard let self, !Task.isCancelled, self.active, self.currentRequestID == request.id else { return }
                    self.phase = .idle; self.currentRequestID = nil; self.previousDraft = nil
                    self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.startFailed.errorDescription
                }
            } onCancel: {
                // Cancelling a task or destroying its model must also stop pending native capture.
                Task { await services.capture.cancel(requestID: request.id) }
            }
        }
    }
    private func captureDidStart(_ session: DictationCaptureSession, language: DictationLanguage) {
        phase = .recording; startedAt = services.now(); draftDate = services.now(); durationSeconds = 0
        draftID = UUID(); savedText = nil; reviewText = ""; draftLanguage = language; microphoneName = session.microphone.name
    }
    private func consume(_ event: DictationCaptureEvent, id: UUID) {
        switch event {
        case .transcript(let value): reviewText = value.text; hasProvisionalText = value.containsProvisionalText
        case .finished(let value, let reachedLimit):
            reviewText = value.text; hasProvisionalText = value.containsProvisionalText; finishReview()
            statusMessage = reachedLimit ? "Five-minute limit reached. Review the available text." : value.text.isEmpty ? "No speech was recognized. Check your microphone and language, then retry." : "Recording stopped. Review and edit before copying or saving."
        case .failed(let error, let value):
            if let value { reviewText = value.text; hasProvisionalText = value.containsProvisionalText }
            finishReview(); errorMessage = error.errorDescription
        case .cancelled: finishReview()
        }
    }
    private func finishReview() {
        if let startedAt { durationSeconds = max(0, services.now().timeIntervalSince(startedAt)) }
        phase = .idle; currentRequestID = nil; startedAt = nil; previousDraft = nil; focusRequest += 1
    }
    func finishRecording() {
        guard phase == .recording, let id = currentRequestID else { return }
        phase = .stopping
        stopWork = Task { [weak self, capture = services.capture] in
            do { try await capture.finish(requestID: id) }
            catch {
                guard let self, self.currentRequestID == id, !Task.isCancelled else { return }
                self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.recognitionFailed.errorDescription
                self.finishReview()
            }
        }
    }
    func cancelRecording() {
        guard let id = currentRequestID else { return }
        currentRequestID = nil; phase = .stopping; work?.cancel(); stopWork?.cancel()
        let prior = work; let token = generation
        stopWork = Task { [weak self, capture = services.capture] in
            await capture.cancel(requestID: id); await prior?.value
            guard let self, self.active, self.generation == token else { return }
            if let previous = self.previousDraft {
                self.reviewText = previous.text; self.draftID = previous.id; self.draftDate = previous.date
                self.draftLanguage = previous.language; self.durationSeconds = previous.duration; self.savedText = previous.savedText
                self.hasProvisionalText = previous.provisional
            }
            self.previousDraft = nil; self.phase = .idle; self.startedAt = nil; self.statusMessage = "Recording cancelled. Previous draft restored."
        }
    }
    func copy() {
        if showsHistory { history.copySelected(); return }
        guard canCopy else { return }; isCopying = true; let text = reviewText
        copyWork = Task { [weak self, pasteboard = services.pasteboard] in
            guard !Task.isCancelled else { return }; await pasteboard.writeString(text)
            guard let self, !Task.isCancelled else { return }; self.isCopying = false; self.statusMessage = "Text copied. Paste it into your app."
        }
    }
    func saveToHistory() {
        guard canSave, let language = draftLanguage ?? language else { return }; isSaving = true; errorMessage = nil
        let value = DictationHistoryEntry(id: draftID, createdAt: draftDate, text: reviewText, languageID: language.id, languageName: language.name, durationSeconds: durationSeconds)
        saveWork = Task { [weak self, store = services.history] in
            do {
                _ = try await store.save(value); try Task.checkCancellation()
                guard let self else { return }; self.isSaving = false
                if self.draftID == value.id { self.savedText = value.text; self.draftLanguage = language }
                self.statusMessage = self.reviewText == value.text ? "Dictation saved to local history." : "Earlier text saved. Your current edits are unsaved."
            } catch {
                guard let self, !Task.isCancelled else { return }; self.isSaving = false
                self.errorMessage = (error as? DictationError)?.errorDescription ?? DictationError.historyUnavailable.errorDescription
            }
        }
    }
    func presentHistory() { guard !isBusy else { return }; showsHistory = true; history.load() }
    func closeHistory() { showsHistory = false; history.stop() }
    func useStylePreview() { guard !isBusy, let value = styles.result(for: reviewText) else { return }; reviewText = value; focusRequest += 1 }
    func openAISettings() { onAISettings() }
    func openMicrophoneSettings() { Task { await services.microphonePermission.openSettings() } }
    func moveSelection(offset: Int) { if showsHistory { history.moveSelection(offset: offset) } }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case DictationActionID.start: requestRecording()
        case DictationActionID.finish: finishRecording()
        case DictationActionID.cancel: cancelRecording()
        case DictationActionID.save: saveToHistory()
        case DictationActionID.history: presentHistory()
        case DictationActionID.settings: openMicrophoneSettings()
        case BuiltInCommandActionID.copy: copy()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        default: break
        }
    }
    func handleEscape() -> Bool {
        if history.showsDeleteConfirmation { history.showsDeleteConfirmation = false; return true }
        if history.showsClearConfirmation { history.showsClearConfirmation = false; return true }
        if showsHistory { closeHistory(); return true }
        if showsLeaveConfirmation { showsLeaveConfirmation = false; return true }
        if showsReplaceConfirmation { showsReplaceConfirmation = false; return true }
        if isDownloading { cancelDownload(); return true }
        if phase != .idle { cancelRecording(); return true }
        if styles.isWorking || styles.originalText != nil { styles.invalidate(); return true }
        if !reviewText.isEmpty, reviewText != savedText { showsLeaveConfirmation = true; return true }
        return false
    }
    func goBack() { if handleEscape() { return }; leaveDiscardingDraft() }
    func leaveDiscardingDraft() { showsLeaveConfirmation = false; stop(); onGoBack() }
    func stop() {
        cancelRecording(); active = false; generation = UUID(); availabilityID = UUID()
        loading?.cancel(); availabilityWork?.cancel(); downloadWork?.cancel(); saveWork?.cancel(); copyWork?.cancel()
        styles.stop(); history.stop(); previousDraft = nil; reviewText = ""; statusMessage = nil; errorMessage = nil
    }
    func waitForLoadingForTesting() async { await loading?.value; await availabilityWork?.value; await styles.waitForLoadingForTesting() }
    func waitForCaptureForTesting() async { await work?.value; await stopWork?.value }
    var pendingCaptureForTesting: Task<Void, Never>? { work }
    func waitForStopForTesting() async { await stopWork?.value }
    func waitForDownloadForTesting() async { await downloadWork?.value; await availabilityWork?.value }
    func waitForSaveForTesting() async { await saveWork?.value }
    func waitForCopyForTesting() async { await copyWork?.value }
}
