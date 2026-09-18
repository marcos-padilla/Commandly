import CommandKit
import Foundation
import Infrastructure
import Observation
import SecurityKit

enum ScreenshotActionID {
    static let capture = CommandActionID(rawValue: "screenshot.capture")
    static let cancel = CommandActionID(rawValue: "screenshot.cancel")
    static let copy = CommandActionID(rawValue: "screenshot.copy")
    static let save = CommandActionID(rawValue: "screenshot.save")
    static let annotate = CommandActionID(rawValue: "screenshot.annotate-cleanshot")
    static let clear = CommandActionID(rawValue: "screenshot.clear")
    static let openSettings = CommandActionID(rawValue: "screenshot.open-settings")
}

@Observable
@MainActor
final class ScreenshotViewModel: LauncherApplicationModel {
    @ObservationIgnored private let services: ScreenshotApplicationServices
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var capturer: (any ScreenshotCapturing)?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    var kind: ScreenshotKind = .region
    var showsCursor = false
    var showsActionsMenu = false
    var showsFileExporter = false
    private(set) var image: ScreenshotImage?
    private(set) var isCapturing = false
    private(set) var isCopying = false
    private(set) var isOpeningAnnotation = false
    private(set) var regionPermission: PermissionState = .notDetermined
    private(set) var errorMessage: String?
    private(set) var statusMessage: String? = "Choose content to capture. Screenshots stay on this Mac."

    init(services: ScreenshotApplicationServices, onGoBack: @escaping () -> Void) {
        self.services = services
        self.onGoBack = onGoBack
    }
    deinit { work?.cancel() }

    var needsSettingsRecovery: Bool { kind == .region && (regionPermission == .denied || regionPermission == .restricted) }
    var isReviewActionBusy: Bool { isCopying || isOpeningAnnotation }
    var suggestedFilename: String { "commandly-screenshot.png" }
    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if isCapturing {
            primary = CommandActionDescriptor(id: ScreenshotActionID.cancel, title: "Cancel", isPrimary: true, keyHint: .escape)
        } else if image != nil {
            primary = CommandActionDescriptor(id: ScreenshotActionID.copy, title: "Copy Screenshot", isPrimary: true, keyHint: .return, isEnabled: isReviewActionBusy == false)
        } else {
            primary = CommandActionDescriptor(id: ScreenshotActionID.capture, title: "Choose and Capture", isPrimary: true, keyHint: .return)
        }
        return [primary, CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }
    var menuActions: [CommandActionDescriptor] {
        [CommandActionDescriptor(id: ScreenshotActionID.capture, title: "New Screenshot", isEnabled: isCapturing == false),
         CommandActionDescriptor(id: ScreenshotActionID.copy, title: "Copy Screenshot", isEnabled: image != nil && isReviewActionBusy == false),
         CommandActionDescriptor(id: ScreenshotActionID.annotate, title: "Open in CleanShot X", isEnabled: image != nil && isReviewActionBusy == false),
         CommandActionDescriptor(id: ScreenshotActionID.save, title: "Save Screenshot", isEnabled: image != nil && isReviewActionBusy == false),
         CommandActionDescriptor(id: ScreenshotActionID.clear, title: "Discard Screenshot", isEnabled: image != nil),
         CommandActionDescriptor(id: ScreenshotActionID.cancel, title: "Cancel Selection", isEnabled: isCapturing),
         CommandActionDescriptor(id: ScreenshotActionID.openSettings, title: "Screen Recording Settings")]
    }

    func capture() {
        guard isCapturing == false else { return }
        stop()
        let requestID = generation
        let request = ScreenshotRequest(kind: kind, showsCursor: showsCursor)
        isCapturing = true
        statusMessage = request.kind == .region ? "Checking access for your selected region…" : "Choose content in the macOS picker…"
        work = Task { [weak self, services] in
            guard let self else { return }
            if request.kind == .region {
                var permission = await services.permissions.state(for: .screenRecording)
                guard generation == requestID, Task.isCancelled == false else { return }
                if permission == .notDetermined { permission = await services.permissions.request(.screenRecording) }
                guard generation == requestID, Task.isCancelled == false else { return }
                regionPermission = permission
                guard permission == .authorized else { isCapturing = false; fail(.permissionRequired); return }
            }
            let capture = services.makeCapture()
            capturer = capture
            statusMessage = request.kind == .region ? "Drag a region, then release to capture. Escape cancels." : "Choose a \(request.kind.rawValue) in the macOS picker."
            do {
                let captured = try await capture.capture(request)
                try Task.checkCancellation()
                guard generation == requestID else { return }
                guard captured.kind == request.kind else { throw ScreenshotCaptureError.invalidImage }
                capturer = nil
                image = captured
                isCapturing = false
                statusMessage = "Review your screenshot. Copy and save are separate actions."
            } catch {
                guard generation == requestID else { return }
                capturer = nil
                isCapturing = false
                if error is CancellationError || error as? ScreenshotCaptureError == .cancelled {
                    statusMessage = "Screenshot selection cancelled."
                } else { fail(error as? ScreenshotCaptureError ?? .captureFailed) }
            }
        }
    }

    func copy() {
        guard let image, isReviewActionBusy == false else { return }
        let requestID = generation
        isCopying = true
        errorMessage = nil
        work = Task { [weak self, services] in
            do {
                try Task.checkCancellation()
                try await services.copier.copyPNG(image.pngData)
                try Task.checkCancellation()
                guard let self, generation == requestID else { return }
                isCopying = false
                statusMessage = "Screenshot copied."
            } catch {
                guard let self, generation == requestID else { return }
                isCopying = false
                fail(.copyFailed)
            }
        }
    }

    func openInCleanShot() {
        guard let image, isReviewActionBusy == false else { return }
        let requestID = generation
        isOpeningAnnotation = true
        errorMessage = nil
        statusMessage = "Opening the reviewed image in CleanShot X…"
        work = Task { [weak self, services] in
            do {
                try Task.checkCancellation()
                try await services.annotator.openInCleanShot(image)
                guard let self, generation == requestID, Task.isCancelled == false else { return }
                isOpeningAnnotation = false
                statusMessage = "Sent to CleanShot X. Finish editing there; Commandly does not read back edits."
            } catch {
                guard let self, generation == requestID else { return }
                isOpeningAnnotation = false
                if error is CancellationError { statusMessage = "CleanShot handoff cancelled." }
                else { annotationFailed(error as? ScreenshotAnnotationError ?? .openFailed) }
            }
        }
    }

    func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success: errorMessage = nil; statusMessage = "Screenshot saved."
        case .failure(let error):
            let native = error as NSError
            guard native.domain != NSCocoaErrorDomain || native.code != NSUserCancelledError else { return }
            errorMessage = "The screenshot couldn’t be saved. Choose another location and try again."
        }
    }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case ScreenshotActionID.capture: capture()
        case ScreenshotActionID.cancel, ScreenshotActionID.clear: stop()
        case ScreenshotActionID.copy: copy()
        case ScreenshotActionID.annotate: openInCleanShot()
        case ScreenshotActionID.save: if image != nil && isReviewActionBusy == false { showsFileExporter = true }
        case ScreenshotActionID.openSettings: Task { [services] in await services.privacySettings.open(.screenRecording) }
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }
    func goBack() { stop(); onGoBack() }
    func moveSelection(offset: Int) { _ = offset }
    func stop() {
        generation += 1
        work?.cancel()
        work = nil
        capturer?.cancel()
        capturer = nil
        image = nil
        isCapturing = false
        isCopying = false
        isOpeningAnnotation = false
        showsFileExporter = false
        showsActionsMenu = false
        errorMessage = nil
        statusMessage = "No screenshot retained."
    }
    func handleEscape() -> Bool {
        if showsFileExporter { showsFileExporter = false; return true }
        if isCapturing { stop(); return true }
        return false
    }
    func waitForWorkForTesting() async { await work?.value }
    func pendingWorkForTesting() -> Task<Void, Never>? { work }

    private func annotationFailed(_ error: ScreenshotAnnotationError) {
        statusMessage = nil
        errorMessage = switch error {
        case .applicationUnavailable: "CleanShot X is not available. Install and open CleanShot X, then retry, or use Save to keep the screenshot."
        case .unexpectedApplication: "The CleanShot link handler is not a verified CleanShot X app. Reopen or reinstall your official CleanShot X copy, then retry."
        case .applicationOutdated: "This action needs CleanShot X 3.8.1 or later. Update your installed copy, then retry."
        case .invalidImage: "This screenshot couldn’t be prepared for annotation. Capture it again or save it instead."
        case .temporaryStorageFailed: "The private handoff file couldn’t be managed. Retry, or save the screenshot and open it from CleanShot X."
        case .temporaryStorageFull: "Temporary annotation storage is full. Wait up to ten minutes for earlier handoffs to expire, then retry, or use Save."
        case .openFailed: "CleanShot X couldn’t accept the image. Open CleanShot X, review any API access prompt there, then retry or open a saved PNG from its editor."
        }
    }

    private func fail(_ error: ScreenshotCaptureError) {
        if error == .permissionRequired && kind == .region && regionPermission == .authorized { regionPermission = .denied }
        errorMessage = switch error {
        case .cancelled: nil
        case .busy: "Another screenshot selection is active. Finish or cancel it, then try again."
        case .permissionRequired: kind == .region
            ? "Region capture needs Screen Recording access. Enable Commandly in Privacy & Security → Screen & System Audio Recording, then retry."
            : "Capture wasn’t authorized. Choose the content again in the macOS picker."
        case .selectionUnavailable: "The macOS selection UI is unavailable. Finish other sharing selections or return to the desktop, then retry."
        case .selectionInvalid: "That selection is unavailable. Choose a visible window, display, or a region at least two points wide and high."
        case .captureFailed: "The screenshot couldn’t be captured. The content may have closed, be protected, or no longer be shared. Choose it again."
        case .invalidImage: "The captured image couldn’t be processed. Try a smaller region or another window."
        case .copyFailed: "The screenshot couldn’t be copied. Try again or save it instead."
        }
    }
}
