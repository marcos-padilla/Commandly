import CommandKit
import Foundation
import Infrastructure
import Observation
import SecurityKit

enum CameraActionID {
    static let start = CommandActionID(rawValue: "camera.start")
    static let capture = CommandActionID(rawValue: "camera.capture")
    static let stop = CommandActionID(rawValue: "camera.stop")
    static let save = CommandActionID(rawValue: "camera.save")
    static let copy = CommandActionID(rawValue: "camera.copy")
    static let openSettings = CommandActionID(rawValue: "camera.open-permission-settings")
}

enum CameraViewState: Equatable {
    case idle, requestingPermission, starting, previewing, capturing, reviewing
    case failed(CameraCaptureError)
}

/// Owns one explicit preview/review flow. Camera factories and permissions are untouched at init.
@Observable
@MainActor
final class CameraViewModel: LauncherApplicationModel {
    @ObservationIgnored private let permissions: any PermissionServicing
    @ObservationIgnored private let makeCapture: @MainActor () -> any CameraCapturing
    @ObservationIgnored private let photoCopier: any CameraPhotoCopying
    @ObservationIgnored private let privacySettingsOpener: any PrivacySettingsOpening
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var capture: (any CameraCapturing)?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var frames: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private(set) var state: CameraViewState = .idle
    private(set) var permissionState: PermissionState = .notDetermined
    private(set) var devices: [CameraDevice] = []
    private(set) var selectedDeviceID: String?
    private(set) var frame: CameraPreviewFrame?
    private(set) var photo: CameraPhoto?
    private(set) var statusMessage: String? = "Camera is off. Start Camera requests access only when needed."
    private(set) var isCopying = false
    var mirrorsImage = true
    var showsActionsMenu = false
    var showsFileExporter = false

    init(permissions: any PermissionServicing, makeCapture: @escaping @MainActor () -> any CameraCapturing,
         photoCopier: any CameraPhotoCopying, privacySettingsOpener: any PrivacySettingsOpening, onGoBack: @escaping () -> Void) {
        self.permissions = permissions
        self.makeCapture = makeCapture
        self.photoCopier = photoCopier
        self.privacySettingsOpener = privacySettingsOpener
        self.onGoBack = onGoBack
    }

    deinit {
        work?.cancel()
        frames?.cancel()
        if let capture { Task { await capture.stop() } }
    }

    var isBusy: Bool { state == .requestingPermission || state == .starting || state == .capturing }
    var canCapture: Bool { state == .previewing && frame != nil }
    var needsSettingsRecovery: Bool { permissionState == .denied || permissionState == .restricted }
    var suggestedFilename: String { "commandly-selfie.png" }

    var footerActions: [CommandActionDescriptor] {
        let primary: CommandActionDescriptor
        if isBusy {
            primary = CommandActionDescriptor(id: CameraActionID.stop, title: "Cancel", isPrimary: true, keyHint: .escape)
        } else if state == .previewing {
            primary = CommandActionDescriptor(id: CameraActionID.capture, title: "Take Photo", isPrimary: true,
                                               keyHint: .return, isEnabled: canCapture)
        } else if photo != nil {
            primary = CommandActionDescriptor(id: CameraActionID.save, title: "Save Photo", isPrimary: true, keyHint: .return)
        } else if needsSettingsRecovery {
            primary = CommandActionDescriptor(id: CameraActionID.openSettings, title: "Open Camera Settings", isPrimary: true, keyHint: .return)
        } else {
            primary = CommandActionDescriptor(id: CameraActionID.start, title: "Start Camera", isPrimary: true, keyHint: .return)
        }
        return [primary, CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(id: CameraActionID.start, title: photo == nil ? "Start Camera" : "Retake Photo", isEnabled: isBusy == false),
            CommandActionDescriptor(id: CameraActionID.capture, title: "Take Photo", isEnabled: canCapture),
            CommandActionDescriptor(id: CameraActionID.save, title: "Save Photo", isEnabled: photo != nil),
            CommandActionDescriptor(id: CameraActionID.copy, title: "Copy Photo", isEnabled: photo != nil && isCopying == false),
            CommandActionDescriptor(id: CameraActionID.stop, title: "Stop and Clear", isEnabled: state != .idle),
            CommandActionDescriptor(id: CameraActionID.openSettings, title: "Open Camera Settings")
        ]
    }

    func start(deviceID: String? = nil) {
        guard isBusy == false else { return }
        stop()
        let request = generation
        let previousCleanup = cleanup
        state = .requestingPermission
        statusMessage = "Checking Camera access…"
        work = Task { [weak self, permissions] in
            var currentPermission = await permissions.state(for: .camera)
            guard Task.isCancelled == false, let self, generation == request else { return }
            if currentPermission == .notDetermined {
                currentPermission = await permissions.request(.camera)
            }
            guard Task.isCancelled == false, generation == request else { return }
            permissionState = currentPermission
            guard currentPermission == .authorized else {
                state = .failed(.permissionRequired)
                statusMessage = currentPermission == .restricted
                    ? "Camera access is restricted by this Mac’s settings."
                    : "Camera access is off. Enable Commandly in Privacy & Security → Camera, then try Start Camera."
                return
            }
            state = .starting
            statusMessage = "Starting camera preview…"
            // Camera ownership must be released before a replacement actor opens any device.
            // Awaiting does not cancel cleanup: Escape must still let the old session shut down.
            await previousCleanup?.value
            guard Task.isCancelled == false, generation == request else { return }
            cleanup = nil
            // Each start receives a fresh actor. A cancelled older start can only stop its own actor.
            let newCapture = makeCapture()
            capture = newCapture
            do {
                let session = try await newCapture.start(deviceID: deviceID)
                try Task.checkCancellation()
                guard generation == request else { await newCapture.stop(); return }
                devices = session.devices
                selectedDeviceID = session.selectedDeviceID
                state = .previewing
                statusMessage = "Camera is on. Preview only; no audio is captured."
                observeFrames(session.events, request: request)
            } catch {
                await newCapture.stop()
                guard generation == request else { return }
                capture = nil
                if error is CancellationError { state = .idle; statusMessage = "Camera stopped." }
                else { fail(error) }
            }
        }
    }

    func selectDevice(_ id: String) {
        guard id != selectedDeviceID, devices.contains(where: { $0.id == id }), isBusy == false else { return }
        start(deviceID: id)
    }

    func takePhoto() {
        guard canCapture, let capture else { return }
        let request = generation
        let mirrored = mirrorsImage
        state = .capturing
        statusMessage = "Taking photo…"
        work = Task { [weak self] in
            do {
                let captured = try await capture.takePhoto(mirrored: mirrored)
                try Task.checkCancellation()
                await capture.stop()
                guard let self, request == generation else { return }
                self.capture = nil
                frames?.cancel()
                frames = nil
                frame = nil
                photo = captured
                state = .reviewing
                statusMessage = "Camera is off. Review your photo, then save or copy it."
            } catch {
                await capture.stop()
                guard let self, request == generation else { return }
                self.capture = nil
                frames?.cancel()
                frames = nil
                frame = nil
                fail(error)
            }
        }
    }

    func copyPhoto() {
        guard let photo, isCopying == false else { return }
        let request = generation
        isCopying = true
        work = Task { [weak self, photoCopier] in
            do {
                try Task.checkCancellation()
                try await photoCopier.copyPNG(photo.pngData)
                try Task.checkCancellation()
                guard let self, request == generation else { return }
                isCopying = false
                statusMessage = "Photo copied."
            } catch {
                guard let self, request == generation else { return }
                isCopying = false
                statusMessage = "The photo couldn’t be copied. You can save it instead."
            }
        }
    }

    func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success: statusMessage = "Photo saved."
        case .failure(let error):
            let cocoa = error as NSError
            guard cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSUserCancelledError else { return }
            statusMessage = "The photo couldn’t be saved. Choose another location and try again."
        }
    }

    func goBack() { stop(); onGoBack() }
    func moveSelection(offset: Int) { _ = offset }
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case CameraActionID.start: start(deviceID: selectedDeviceID)
        case CameraActionID.capture: takePhoto()
        case CameraActionID.stop: stop()
        case CameraActionID.save: if photo != nil { showsFileExporter = true }
        case CameraActionID.copy: copyPhoto()
        case CameraActionID.openSettings:
            Task { [privacySettingsOpener] in await privacySettingsOpener.open(.camera) }
        case BuiltInCommandActionID.openActions: showsActionsMenu = true
        default: break
        }
    }

    func stop() {
        generation += 1
        work?.cancel()
        frames?.cancel()
        work = nil
        frames = nil
        if let capture {
            cleanup = Task { await capture.stop() }
        }
        capture = nil
        frame = nil
        photo = nil
        devices = []
        selectedDeviceID = nil
        state = .idle
        isCopying = false
        showsFileExporter = false
        showsActionsMenu = false
        statusMessage = "Camera is off."
    }

    func handleEscape() -> Bool {
        if showsFileExporter { showsFileExporter = false; return true }
        if isBusy || state == .previewing { stop(); return true }
        return false
    }

    func waitForWorkForTesting() async { await work?.value }
    func waitForCleanupForTesting() async { await cleanup?.value }
    func pendingWorkForTesting() -> Task<Void, Never>? { work }

    private func observeFrames(_ events: AsyncStream<CameraCaptureEvent>, request: Int) {
        frames = Task { [weak self] in
            for await event in events {
                guard Task.isCancelled == false, let self, request == generation else { return }
                switch event {
                case .frame(let next): frame = next
                case .failed(let error):
                    generation += 1
                    work?.cancel()
                    if let capture { cleanup = Task { await capture.stop() } }
                    frame = nil
                    capture = nil
                    fail(error)
                    return
                case .stopped:
                    frame = nil
                    if state == .previewing { state = .idle; statusMessage = "Camera stopped." }
                }
            }
            guard Task.isCancelled == false, let self, request == generation, state == .previewing else { return }
            if let capture { cleanup = Task { await capture.stop() } }
            capture = nil
            frame = nil
            fail(CameraCaptureError.interrupted)
        }
    }

    private func fail(_ error: Error) {
        let failure = error as? CameraCaptureError ?? .captureFailed
        state = .failed(failure)
        statusMessage = switch failure {
        case .permissionRequired: "Camera access is required. Check Privacy & Security → Camera."
        case .noCamera: "No camera was found. Connect a camera, then try Start Camera."
        case .deviceUnavailable: "That camera disconnected. Choose Start Camera to refresh connected devices."
        case .startFailed: "The camera couldn’t start. Close other camera apps or choose another device and try again."
        case .interrupted: "Camera preview was interrupted. Choose Start Camera to retry."
        case .captureUnavailable, .captureFailed: "The photo couldn’t be taken. Restart the camera and try again."
        case .encodingFailed, .invalidFrame: "The camera image couldn’t be processed. Restart the camera and try again."
        case .copyFailed: "The photo couldn’t be copied. Try saving it instead."
        }
    }
}
