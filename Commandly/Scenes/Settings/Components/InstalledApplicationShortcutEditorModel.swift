import Foundation
import Observation

struct InstalledApplicationShortcutSummary: Identifiable {
    let bundleIdentifier: String
    let applicationName: String
    let hotKey: LauncherHotKey
    var id: String { bundleIdentifier }
}

/// Drafts one exact installed application's shortcut; recording alone never changes registration.
@MainActor
@Observable
final class InstalledApplicationShortcutEditorModel: Identifiable {
    let bundleIdentifier: String
    let applicationName: String
    var id: String { bundleIdentifier }
    var hotKey: LauncherHotKey? { didSet { errorMessage = nil } }
    private(set) var errorMessage: String?
    private(set) var isRecording = false
    private(set) var showsOtherAssignments = false
    private(set) var otherAssignments: [InstalledApplicationShortcutSummary] = []
    private(set) var managementMessage: String?
    @ObservationIgnored private let original: LauncherHotKey?
    @ObservationIgnored private let saveAssignment: (String, LauncherHotKey?) -> String?
    @ObservationIgnored private let onSaved: () -> Void
    @ObservationIgnored private let onCancel: () -> Void
    @ObservationIgnored private let onRecordingChange: (Bool) -> Void
    @ObservationIgnored private let loadAssignments: () -> [InstalledApplicationShortcutSummary]

    init(
        bundleIdentifier: String,
        applicationName: String,
        hotKey: LauncherHotKey?,
        initialIssue: String? = nil,
        saveAssignment: @escaping (String, LauncherHotKey?) -> String?,
        onRecordingChange: @escaping (Bool) -> Void = { _ in },
        loadAssignments: @escaping () -> [InstalledApplicationShortcutSummary] = { [] },
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.hotKey = hotKey
        errorMessage = initialIssue
        original = hotKey
        self.saveAssignment = saveAssignment
        self.onRecordingChange = onRecordingChange
        self.loadAssignments = loadAssignments
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var canSave: Bool { !isRecording && hotKey != original && (hotKey.map(InstalledApplicationShortcuts.isSupported) ?? true) }
    var removesShortcut: Bool { original != nil && hotKey == nil }

    func save() {
        guard canSave else { return }
        if let error = saveAssignment(bundleIdentifier, hotKey) {
            errorMessage = error
        } else {
            onSaved()
        }
    }

    func recordingChanged(_ value: Bool) {
        guard isRecording != value else { return }
        isRecording = value
        onRecordingChange(value)
    }

    func toggleOtherAssignments() {
        showsOtherAssignments.toggle()
        managementMessage = nil
        refreshOtherAssignments()
    }

    func removeOtherAssignment(_ bundleID: String) {
        guard !isRecording, bundleID != bundleIdentifier,
              let assignment = otherAssignments.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        if let error = saveAssignment(bundleID, nil) {
            managementMessage = error
        } else {
            managementMessage = "Shortcut removed for \(assignment.applicationName)."
            refreshOtherAssignments()
        }
    }

    private func refreshOtherAssignments() {
        otherAssignments = loadAssignments().filter { $0.bundleIdentifier != bundleIdentifier }
    }

    func cancel() {
        recordingChanged(false)
        onCancel()
    }
}
