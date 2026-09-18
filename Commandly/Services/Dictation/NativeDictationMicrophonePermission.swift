import AppKit
import AVFoundation
import Foundation
import Infrastructure

/// Instantiation is inert; the only prompt path is requestAuthorization after explicit Start.
@MainActor
struct NativeDictationMicrophonePermission: DictationMicrophoneAuthorizing {
    private let preflight: @MainActor @Sendable () -> AVAuthorizationStatus
    private let request: @MainActor @Sendable () async -> Bool
    private let settings: @MainActor @Sendable () -> Void
    init(preflight: @escaping @MainActor @Sendable () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
         request: @escaping @MainActor @Sendable () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
         settings: @escaping @MainActor @Sendable () -> Void = {
             if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
         }) { self.preflight = preflight; self.request = request; self.settings = settings }
    func authorization() async -> DictationMicrophoneAuthorization {
        switch preflight() {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
    func requestAuthorization() async -> DictationMicrophoneAuthorization {
        let state = await authorization()
        guard state == .notDetermined, !Task.isCancelled else { return state }
        return await request() ? .authorized : .denied
    }
    func openSettings() async { settings() }
}
