import AppKit
import ApplicationServices
import Contacts
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

    init(
        folderAccessStore: any FolderAccessStoring,
        eventStoreFactory: @escaping @Sendable () -> EKEventStore = { EKEventStore() },
        contactStoreFactory: @escaping @Sendable () -> CNContactStore = { CNContactStore() }
    ) {
        self.folderAccessStore = folderAccessStore
        self.eventStoreFactory = eventStoreFactory
        self.contactStoreFactory = contactStoreFactory
    }

    func state(for kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .calendar:
            return mapEventKitStatus(EKEventStore.authorizationStatus(for: .event))
        case .contacts:
            return mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
        case .accessibility:
            return AXIsProcessTrusted() ? .authorized : .notDetermined
        case .files:
            let hasAccess = await MainActor.run {
                folderAccessStore.hasUsableAccess
            }
            return hasAccess ? .authorized : .notDetermined
        case .notifications, .appleEvents, .screenRecording:
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
        case .notifications, .appleEvents, .screenRecording:
            return .notDetermined
        }
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

    private func requestAccessibilityAccess() async -> PermissionState {
        if AXIsProcessTrusted() {
            return .authorized
        }

        // Literal key avoids importing a non-Sendable global CF constant into concurrency checks.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        return trusted ? .authorized : .denied
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
