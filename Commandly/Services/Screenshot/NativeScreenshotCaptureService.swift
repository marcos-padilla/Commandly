import AppKit
import CoreGraphics
import Foundation
import Infrastructure
import QuartzCore
import ScreenCaptureKit

/// One interactive selection at a time. Initialization does not touch picker, windows, screen metadata, or TCC.
@MainActor
final class NativeScreenshotCaptureService: ScreenshotCapturing {
    private let regionSelector: any ScreenshotRegionSelecting
    private let renderer: ScreenshotImageRenderer
    private let regionPreflight: @MainActor () -> Bool
    private let displayLayout: @MainActor () throws -> ScreenshotDisplayLayout
    private var operationID: UUID?
    private var request: ScreenshotRequest?
    private var continuation: CheckedContinuation<ScreenshotImage, Error>?
    private var work: Task<Void, Never>?
    private var pickerObserver: ScreenshotSystemPickerObserver?
    private var previousPickerConfiguration: SCContentSharingPickerConfiguration?
    private weak var launcherWindow: NSWindow?
    private var launcherAlpha: CGFloat = 1
    private var launcherIgnoredMouse = false
    private var displayObserver: NSObjectProtocol?
    private var selectedLayout: ScreenshotDisplayLayout?

    init(regionSelector: any ScreenshotRegionSelecting = ScreenshotRegionSelector(),
         renderer: ScreenshotImageRenderer = ScreenshotImageRenderer(),
         regionPreflight: @escaping @MainActor () -> Bool = { CGPreflightScreenCaptureAccess() },
         displayLayout: @escaping @MainActor () throws -> ScreenshotDisplayLayout = { try ScreenshotNativeDisplayLayout.current() }) {
        self.regionSelector = regionSelector
        self.renderer = renderer
        self.regionPreflight = regionPreflight
        self.displayLayout = displayLayout
    }

    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage {
        try Task.checkCancellation()
        guard operationID == nil else { throw ScreenshotCaptureError.busy }
        let id = UUID()
        let image = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operationID = id
                self.request = request
                self.continuation = continuation
                concealLauncher()
                if request.kind == .region { beginRegion(request, id: id) }
                else { beginPicker(request, id: id) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
        try Task.checkCancellation()
        return image
    }

    func cancel() {
        guard let operationID else { return }
        cancel(id: operationID)
    }

    private func beginPicker(_ request: ScreenshotRequest, id: UUID) {
        let picker = SCContentSharingPicker.shared
        guard picker.isActive == false, picker.isAvailable else { finish(.failure(ScreenshotCaptureError.selectionUnavailable), id: id); return }
        previousPickerConfiguration = picker.defaultConfiguration
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = request.kind == .window ? [.singleWindow] : [.singleDisplay]
        configuration.allowsChangingSelectedContent = false
        if let bundleID = Bundle.main.bundleIdentifier { configuration.excludedBundleIDs = [bundleID] }
        picker.defaultConfiguration = configuration
        let observer = ScreenshotSystemPickerObserver(request: request) { [weak self] result in
            Task { @MainActor in self?.received(result, id: id) }
        }
        pickerObserver = observer
        picker.add(observer)
        picker.isActive = true
        picker.present(using: request.kind == .window ? .window : .display)
    }

    private func beginRegion(_ request: ScreenshotRequest, id: UUID) {
        guard regionPreflight() else { finish(.failure(ScreenshotCaptureError.permissionRequired), id: id); return }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finish(.failure(ScreenshotCaptureError.selectionInvalid), id: id) }
        }
        work = Task { [weak self, regionSelector] in
            do {
                let region = try await regionSelector.select()
                try Task.checkCancellation()
                guard let self, operationID == id else { return }
                guard regionPreflight() else { finish(.failure(ScreenshotCaptureError.permissionRequired), id: id); return }
                guard region.layout == (try displayLayout()) else { throw ScreenshotCaptureError.selectionInvalid }
                selectedLayout = region.layout
                let configuration = try ScreenshotNativeConfiguration.make(points: region.captureRect.size, scale: region.scale, showsCursor: request.showsCursor)
                SCScreenshotManager.captureScreenshot(rect: region.captureRect, configuration: configuration) { [weak self] output, error in
                    let result: Result<CGImage, ScreenshotCaptureError>
                    if let error { result = .failure(ScreenshotNativeConfiguration.failure(error)) }
                    else if let image = output?.sdrImage { result = .success(image) }
                    else { result = .failure(.captureFailed) }
                    Task { @MainActor in self?.received(result, id: id) }
                }
            } catch {
                guard let self, operationID == id else { return }
                finish(.failure(error), id: id)
            }
        }
    }

    private func received(_ result: Result<CGImage, ScreenshotCaptureError>, id: UUID) {
        guard operationID == id, let request else { return }
        if request.kind == .region {
            do {
                guard let selectedLayout, selectedLayout == (try displayLayout()) else {
                    finish(.failure(ScreenshotCaptureError.selectionInvalid), id: id); return
                }
            } catch { finish(.failure(ScreenshotCaptureError.selectionInvalid), id: id); return }
        }
        switch result {
        case .failure(let error): finish(.failure(error), id: id)
        case .success(let image):
            work = Task { [weak self, renderer] in
                do {
                    let artifact = try await renderer.render(image, kind: request.kind)
                    try Task.checkCancellation()
                    guard let self, operationID == id else { return }
                    if request.kind == .region {
                        guard regionPreflight() else { finish(.failure(ScreenshotCaptureError.permissionRequired), id: id); return }
                        guard let selectedLayout, selectedLayout == (try displayLayout()) else {
                            finish(.failure(ScreenshotCaptureError.selectionInvalid), id: id); return
                        }
                    }
                    finish(.success(artifact), id: id)
                } catch {
                    guard let self, operationID == id else { return }
                    finish(.failure(error), id: id)
                }
            }
        }
    }

    private func cancel(id: UUID) {
        guard operationID == id else { return }
        finish(.failure(CancellationError()), id: id)
    }

    private func finish(_ result: Result<ScreenshotImage, Error>, id: UUID) {
        guard operationID == id else { return }
        operationID = nil
        request = nil
        selectedLayout = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        let pending = continuation
        continuation = nil
        work?.cancel()
        work = nil
        regionSelector.cancel()
        if let observer = pickerObserver {
            observer.invalidate()
            let picker = SCContentSharingPicker.shared
            picker.remove(observer)
            picker.isActive = false
            if let previousPickerConfiguration { picker.defaultConfiguration = previousPickerConfiguration }
        }
        pickerObserver = nil
        previousPickerConfiguration = nil
        restoreLauncher()
        pending?.resume(with: result)
    }

    private func concealLauncher() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "commandly.launcher" && $0.isVisible }) else { return }
        launcherWindow = window
        launcherAlpha = window.alphaValue
        launcherIgnoredMouse = window.ignoresMouseEvents
        // Retain the launcher session while keeping its UI out of the selected screenshot.
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        CATransaction.flush()
    }

    private func restoreLauncher() {
        guard let window = launcherWindow else { return }
        window.alphaValue = launcherAlpha
        window.ignoresMouseEvents = launcherIgnoredMouse
        if window.isVisible { window.makeKeyAndOrderFront(nil) }
        launcherWindow = nil
    }
}
