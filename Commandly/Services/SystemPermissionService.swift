import AppKit
import ApplicationServices
import AVFoundation
import Contacts
import CoreGraphics
import EventKit
import Foundation
import SecurityKit

/// Production permission adapter. Prompts only when `request` is called after user intent.
///
/// `@unchecked Sendable`: wraps thread-safe system frameworks and a Sendable folder-access store;
/// all prompting APIs are invoked from cooperative async contexts / MainActor where required.
final class SystemPermissionService: PermissionServicing, @unchecked Sendable {
    struct FilesAccessPanelConfiguration: Equatable, Sendable {
        let canChooseFiles: Bool
        let canChooseDirectories: Bool
        let allowsMultipleSelection: Bool
        let prompt: String
        let message: String
        let directoryURL: URL
    }

    private let folderAccessStore: any FolderAccessStoring
    private let eventStoreFactory: @Sendable () -> EKEventStore
    private let contactStoreFactory: @Sendable () -> CNContactStore
    private let accessibilityPreflight: @MainActor @Sendable () -> Bool
    private let accessibilityRequest: @MainActor @Sendable () -> Bool
    private let accessibilityWasRequested: @MainActor @Sendable () -> Bool
    private let markAccessibilityRequested: @MainActor @Sendable () -> Void
    private let screenRecordingPreflight: @MainActor @Sendable () -> Bool
    private let screenRecordingRequest: @MainActor @Sendable () -> Bool
    private let screenRecordingWasRequested: @MainActor @Sendable () -> Bool
    private let markScreenRecordingRequested: @MainActor @Sendable () -> Void
    private let cameraPreflight: @MainActor @Sendable () -> AVAuthorizationStatus
    private let cameraRequest: @MainActor @Sendable () async -> Bool

    init(
        folderAccessStore: any FolderAccessStoring,
        eventStoreFactory: @escaping @Sendable () -> EKEventStore = { EKEventStore() },
        contactStoreFactory: @escaping @Sendable () -> CNContactStore = { CNContactStore() },
        accessibilityPreflight: @escaping @MainActor @Sendable () -> Bool = {
            AXIsProcessTrusted()
        },
        accessibilityRequest: @escaping @MainActor @Sendable () -> Bool = {
            // Literal key avoids importing a non-Sendable global CF constant into concurrency
            // checks.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        accessibilityWasRequested: @escaping @MainActor @Sendable () -> Bool = {
            AccessibilityRequestMarker.wasRequested
        },
        markAccessibilityRequested: @escaping @MainActor @Sendable () -> Void = {
            AccessibilityRequestMarker.markRequested()
        },
        screenRecordingPreflight: @escaping @MainActor @Sendable () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        screenRecordingRequest: @escaping @MainActor @Sendable () -> Bool = {
            CGRequestScreenCaptureAccess()
        },
        screenRecordingWasRequested: @escaping @MainActor @Sendable () -> Bool = {
            ScreenRecordingRequestMarker.wasRequested
        },
        markScreenRecordingRequested: @escaping @MainActor @Sendable () -> Void = {
            ScreenRecordingRequestMarker.markRequested()
        },
        cameraPreflight: @escaping @MainActor @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        cameraRequest: @escaping @MainActor @Sendable () async -> Bool = {
            await AVCaptureDevice.requestAccess(for: .video)
        }
    ) {
        self.folderAccessStore = folderAccessStore
        self.eventStoreFactory = eventStoreFactory
        self.contactStoreFactory = contactStoreFactory
        self.accessibilityPreflight = accessibilityPreflight
        self.accessibilityRequest = accessibilityRequest
        self.accessibilityWasRequested = accessibilityWasRequested
        self.markAccessibilityRequested = markAccessibilityRequested
        self.screenRecordingPreflight = screenRecordingPreflight
        self.screenRecordingRequest = screenRecordingRequest
        self.screenRecordingWasRequested = screenRecordingWasRequested
        self.markScreenRecordingRequested = markScreenRecordingRequested
        self.cameraPreflight = cameraPreflight
        self.cameraRequest = cameraRequest
    }

    func state(for kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .calendar:
            return mapEventKitStatus(EKEventStore.authorizationStatus(for: .event))
        case .contacts:
            return mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
        case .accessibility:
            return await accessibilityState()
        case .files:
            let hasAccess = await MainActor.run {
                folderAccessStore.hasUsableAccess
            }
            return hasAccess ? .authorized : .notDetermined
        case .screenRecording:
            return await screenRecordingState()
        case .camera:
            return await cameraState()
        case .notifications, .appleEvents:
            return .notDetermined
        }
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .calendar:
            return await requestCalendarAccess()
        case .contacts:
            return await requestContactsAccess()
        case .accessibility:
            return await requestAccessibilityAccess()
        case .files:
            return await requestFilesAccess()
        case .screenRecording:
            return await requestScreenRecordingAccess()
        case .camera:
            return await requestCameraAccess()
        case .notifications, .appleEvents:
            return .notDetermined
        }
    }

    @MainActor
    private func cameraState() -> PermissionState {
        switch cameraPreflight() {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    @MainActor
    private func requestCameraAccess() async -> PermissionState {
        let currentState = cameraState()
        // AVFoundation retains the authorization decision. Denied and restricted users recover
        // through System Settings; preflight never constructs a capture input or starts a camera.
        guard currentState == .notDetermined, Task.isCancelled == false else {
            return currentState
        }
        return await cameraRequest() ? .authorized : .denied
    }

    @MainActor
    private func accessibilityState() -> PermissionState {
        if accessibilityPreflight() {
            return .authorized
        }
        return accessibilityWasRequested() ? .denied : .notDetermined
    }

    @MainActor
    private func screenRecordingState() -> PermissionState {
        if screenRecordingPreflight() {
            return .authorized
        }
        return screenRecordingWasRequested() ? .denied : .notDetermined
    }

    @MainActor
    private func requestScreenRecordingAccess() -> PermissionState {
        if screenRecordingPreflight() {
            return .authorized
        }
        guard Task.isCancelled == false else {
            return screenRecordingWasRequested() ? .denied : .notDetermined
        }

        // Persist before invoking the synchronous TCC request so a termination during the system
        // flow cannot make a later preflight failure look like permission was never requested.
        markScreenRecordingRequested()
        return screenRecordingRequest() ? .authorized : .denied
    }

    private func requestCalendarAccess() async -> PermissionState {
        let store = eventStoreFactory()
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            return await state(for: .calendar)
        }
    }

    private func requestContactsAccess() async -> PermissionState {
        let store = contactStoreFactory()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            return granted ? .authorized : .denied
        } catch {
            return await state(for: .contacts)
        }
    }

    @MainActor
    private func requestAccessibilityAccess() -> PermissionState {
        if accessibilityPreflight() {
            return .authorized
        }

        // Persist before the synchronous TCC request so relaunching during the Settings flow cannot
        // make a later failed preflight look like the permission was never requested.
        markAccessibilityRequested()
        return accessibilityRequest() ? .authorized : .denied
    }

    @MainActor
    private func requestFilesAccess() async -> PermissionState {
        let panel = Self.makeFilesAccessPanel()

        let response = await panel.beginSheetModalIfPossible()
        guard response == .OK else {
            return folderAccessStore.hasUsableAccess ? .authorized : .denied
        }

        var bookmarks: [Data] = []
        for url in panel.urls {
            do {
                let data = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                bookmarks.append(data)
            } catch {
                continue
            }
        }

        if bookmarks.isEmpty {
            return .denied
        }

        folderAccessStore.saveBookmarks(bookmarks)
        return .authorized
    }

    @MainActor
    static func makeFilesAccessPanel() -> NSOpenPanel {
        let configuration = filesAccessPanelConfiguration
        let panel = NSOpenPanel()
        panel.canChooseFiles = configuration.canChooseFiles
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.prompt = configuration.prompt
        panel.message = configuration.message
        panel.directoryURL = configuration.directoryURL
        return panel
    }

    static var filesAccessPanelConfiguration: FilesAccessPanelConfiguration {
        FilesAccessPanelConfiguration(
            canChooseFiles: false,
            canChooseDirectories: true,
            allowsMultipleSelection: true,
            prompt: "Choose Folders",
            message: "Choose one or more specific folders Commandly can search and manage. "
                + "For safety, Finder AI cannot use your Home folder, folders above Home, or an "
                + "entire volume as a scope. Choose narrower folders for Finder AI; you can change "
                + "scopes later in Settings.",
            directoryURL: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private func mapEventKitStatus(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted, .writeOnly:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }

    private func mapContactsStatus(_ status: CNAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .limited:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }
}

@MainActor
private enum AccessibilityRequestMarker {
    private static let key = "permissions.accessibility.requested.v1"

    static var wasRequested: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markRequested() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

@MainActor
private enum ScreenRecordingRequestMarker {
    private static let key = "permissions.screenRecording.requested.v1"

    static var wasRequested: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markRequested() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

private extension NSOpenPanel {
    @MainActor
    func beginSheetModalIfPossible() async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await beginSheetModal(for: window)
        }
        return await withCheckedContinuation { continuation in
            begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
