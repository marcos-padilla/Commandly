import AIKit
import Foundation
import Infrastructure
import Observation
import SecurityKit

@Observable @MainActor final class VisualAIModel {
    var kind: ScreenshotKind = .display
    var prompt = "Explain what is shown in this screenshot."
    var selectedID: String?
    var showsActionsMenu = false
    private(set) var selections: [VisualAISelection] = []
    private(set) var image: AIImageInput?
    private(set) var response = ""
    private(set) var message: String?
    private(set) var isCapturing = false
    private(set) var isSending = false
    private(set) var isLoading = false
    private(set) var needsPermissionRecovery = false
    @ObservationIgnored private let services: VisualAIApplicationServices
    @ObservationIgnored private let openAISettings: () -> Void
    @ObservationIgnored private let goBackAction: () -> Void
    @ObservationIgnored private var capturer: (any ScreenshotCapturing)?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var catalogWork: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    init(services: VisualAIApplicationServices, openAISettings: @escaping () -> Void, goBack: @escaping () -> Void) {
        self.services = services; self.openAISettings = openAISettings; goBackAction = goBack
    }
    deinit { work?.cancel(); catalogWork?.cancel() }
    var selected: VisualAISelection? { selections.first { $0.id == selectedID } }
    var isWorking: Bool { isCapturing || isSending }
    var canSend: Bool { !isWorking && image != nil && selected != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prompt.utf8.count <= 32_768 }
    func loadModels() {
        guard !isLoading else { return }
        let token = generation; isLoading = true
        catalogWork = Task { [weak self, services] in
            do {
                let values = try await services.ai.selections()
                guard let self, token == generation, !Task.isCancelled else { return }
                selections = values; isLoading = false
                if !values.contains(where: { $0.id == selectedID }) { selectedID = values.first?.id }
                if values.isEmpty { message = "Save a supported image-capable model in AI Settings, then refresh models here. Opening this screen sends nothing." }
            } catch {
                guard let self, token == generation else { return }
                isLoading = false; message = "Saved AI connections could not be read. Open AI Settings and try again."
            }
        }
    }
    func capture() {
        guard !isWorking, kind == .display || kind == .region else { return }
        clearImage(); let token = generation
        let request = ScreenshotRequest(kind: kind, showsCursor: false)
        isCapturing = true; needsPermissionRecovery = false
        message = request.kind == .region ? "Choose a region. Screen Recording access is needed only for this capture mode." : "Choose one full display in the macOS picker."
        work = Task { [weak self, services] in
            guard let self else { return }
            if request.kind == .region {
                var permission = await services.screenshots.permissions.state(for: .screenRecording)
                guard token == generation, !Task.isCancelled else { return }
                if permission == .notDetermined { permission = await services.screenshots.permissions.request(.screenRecording) }
                guard token == generation, !Task.isCancelled else { return }
                guard permission == .authorized else {
                    isCapturing = false; needsPermissionRecovery = true
                    message = "Region capture needs Screen Recording access. Open System Settings, enable Commandly, and retry. No image was sent."; return
                }
            }
            let capture = services.screenshots.makeCapture(); capturer = capture
            do {
                let screenshot = try await capture.capture(request)
                try Task.checkCancellation()
                guard token == generation else { return }
                guard screenshot.kind == request.kind else { throw ScreenshotCaptureError.invalidImage }
                let prepared = try await services.imagePreparer.prepare(screenshot)
                guard token == generation, !Task.isCancelled else { return }
                capturer = nil; isCapturing = false; image = prepared
                message = "Review this exact image before sending. Capture alone does not contact a provider."
            } catch {
                guard token == generation else { return }
                capturer = nil; isCapturing = false
                if error is CancellationError || error as? ScreenshotCaptureError == .cancelled { message = "Capture canceled. No image was sent." }
                else if error as? ScreenshotCaptureError == .permissionRequired {
                    needsPermissionRecovery = request.kind == .region; message = "Screen capture access was unavailable or revoked. Choose the content again or review Screen Recording settings."
                } else { message = "The screenshot could not be prepared. Try a smaller region or select the display again. No image was sent." }
            }
        }
    }
    func send() {
        guard canSend, let image, let selection = selected else { return }
        let token = generation; let question = prompt
        isSending = true; response = ""; message = "Sending this screenshot and question to \(selection.providerName)…"
        work = Task { [weak self, services] in
            do {
                let answer = try await services.ai.respond(prompt: question, image: image, selection: selection)
                guard let self, token == generation, !Task.isCancelled else { return }
                isSending = false; response = answer; message = "Response from \(selection.title). AI answers can be mistaken."
            } catch {
                guard let self, token == generation else { return }
                isSending = false
                if error is CancellationError { message = "Request canceled. Data already sent cannot be recalled." }
                else if error as? AIProviderRuntimeError == .connectionMismatch {
                    message = "The saved provider or credential changed. Refresh models and review the destination before sending again."
                    selections = []; selectedID = nil
                } else { message = "The provider could not complete this request. Check AI Settings or retry explicitly. Data may already have reached the provider." }
            }
        }
    }
    func clearImage() {
        let wasSending = isSending
        generation = UUID(); work?.cancel(); capturer?.cancel(); capturer = nil
        catalogWork?.cancel(); isLoading = false
        image = nil; response = ""; isCapturing = false; isSending = false
        message = wasSending ? "Canceled and removed the local image. Data already sent cannot be recalled." : nil
    }
    func cancel() { let wasSending = isSending; clearImage(); message = wasSending ? "Request canceled. Data already sent cannot be recalled." : "Capture canceled. No image was sent." }
    func stop() { clearImage(); selections = []; selectedID = nil; prompt = ""; showsActionsMenu = false; message = nil }
    func goBack() { stop(); goBackAction() }
    func configureAI() { openAISettings() }
    func openScreenSettings() { Task { [services] in await services.screenshots.privacySettings.open(.screenRecording) } }
    func waitForWorkForTesting() async { await work?.value }
    func waitForCatalogForTesting() async { await catalogWork?.value }
}
