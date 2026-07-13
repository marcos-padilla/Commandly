import CommandKit
import Foundation
import Observation

enum WindowLayoutSource: String, CaseIterable, Identifiable {
    case builtIn
    case custom

    var id: String { rawValue }
    var title: String { self == .builtIn ? "58 Presets" : "Custom" }
}

enum WindowLayoutsActionID {
    static let apply = CommandActionID(rawValue: "window-layout.apply")
    static let newCustom = CommandActionID(rawValue: "window-layout.new-custom")
    static let saveCustom = CommandActionID(rawValue: "window-layout.save-custom")
    static let cancelCustom = CommandActionID(rawValue: "window-layout.cancel-custom")
}

@Observable
@MainActor
final class WindowLayoutsViewModel {
    private let service: any WindowLayoutApplying
    private let customStore: any CustomWindowLayoutStoring
    private let uuidProvider: () -> UUID
    private let onGoBack: () -> Void

    var query = "" {
        didSet { refreshSelection() }
    }
    var source: WindowLayoutSource = .builtIn {
        didSet { refreshSelection() }
    }
    var selectedID: String?
    var showsActionsMenu = false
    private(set) var statusMessage: String?
    private(set) var isApplying = false
    private(set) var customLayouts: [CustomWindowLayout]
    private(set) var isEditingCustom = false
    var customTitle = ""
    var customX = 0.1
    var customY = 0.1
    var customWidth = 0.8
    var customHeight = 0.8

    @ObservationIgnored private var applyTask: Task<Void, Never>?

    init(
        service: any WindowLayoutApplying,
        customStore: any CustomWindowLayoutStoring,
        uuidProvider: @escaping () -> UUID = UUID.init,
        onGoBack: @escaping () -> Void
    ) {
        self.service = service
        self.customStore = customStore
        self.uuidProvider = uuidProvider
        self.onGoBack = onGoBack
        do {
            self.customLayouts = try customStore.load()
        } catch {
            self.customLayouts = []
            self.statusMessage = error.localizedDescription
        }
        self.selectedID = WindowLayoutCatalog.presets.first?.id
    }

    var filteredPresets: [WindowLayoutPreset] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let values: [WindowLayoutPreset]
        switch source {
        case .builtIn:
            values = WindowLayoutCatalog.presets
        case .custom:
            values = customLayouts.map {
                WindowLayoutPreset(
                    id: "custom.\($0.id.uuidString)",
                    title: $0.title,
                    family: .featured,
                    rect: $0.rect
                )
            }
        }
        guard needle.isEmpty == false else { return values }
        return values.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.family.title.localizedCaseInsensitiveContains(needle)
        }
    }

    var selectedPreset: WindowLayoutPreset? {
        filteredPresets.first(where: { $0.id == selectedID }) ?? filteredPresets.first
    }

    var footerActions: [CommandActionDescriptor] {
        if isEditingCustom {
            return [
                CommandActionDescriptor(
                    id: WindowLayoutsActionID.saveCustom,
                    title: "Save Layout",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: customDraftIsValid
                ),
                CommandActionDescriptor(id: WindowLayoutsActionID.cancelCustom, title: "Cancel")
            ]
        }
        return [
            CommandActionDescriptor(
                id: WindowLayoutsActionID.apply,
                title: isApplying ? "Applying…" : "Apply to Active Window",
                isPrimary: true,
                keyHint: .return,
                isEnabled: selectedPreset != nil && isApplying == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        [
            CommandActionDescriptor(
                id: WindowLayoutsActionID.apply,
                title: "Apply to Active Window",
                isEnabled: selectedPreset != nil && isApplying == false
            ),
            CommandActionDescriptor(id: WindowLayoutsActionID.newCustom, title: "New Custom Layout"),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.delete,
                title: "Delete Custom Layout",
                isEnabled: selectedCustomID != nil
            )
        ]
    }

    var customDraftRect: NormalizedWindowRect {
        NormalizedWindowRect(
            x: customX,
            y: customY,
            width: customWidth,
            height: customHeight
        )
    }

    var customDraftIsValid: Bool {
        customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && customDraftRect.isValid
    }

    func select(_ id: String) {
        selectedID = id
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        selectedID = LauncherListSelection.nextID(
            in: filteredPresets,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        )
        statusMessage = nil
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case WindowLayoutsActionID.apply:
            applySelected()
        case WindowLayoutsActionID.newCustom:
            beginCustomEditor()
        case WindowLayoutsActionID.saveCustom:
            saveCustom()
        case WindowLayoutsActionID.cancelCustom:
            cancelCustomEditor()
        case BuiltInCommandActionID.delete:
            deleteSelectedCustom()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case BuiltInCommandActionID.goBack:
            onGoBack()
        default:
            break
        }
    }

    func applySelected() {
        guard let preset = selectedPreset, isApplying == false else { return }
        isApplying = true
        statusMessage = nil
        showsActionsMenu = false
        applyTask?.cancel()
        applyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.apply(rect: preset.rect)
                guard Task.isCancelled == false else { return }
                statusMessage = "Applied \(preset.title)."
            } catch let error as WindowLayoutServiceError {
                statusMessage = error.message
            } catch {
                statusMessage = WindowLayoutServiceError.operationFailed.message
            }
            isApplying = false
        }
    }

    func beginCustomEditor() {
        customTitle = ""
        customX = 0.1
        customY = 0.1
        customWidth = 0.8
        customHeight = 0.8
        isEditingCustom = true
        showsActionsMenu = false
        statusMessage = nil
    }

    func saveCustom() {
        guard customDraftIsValid else {
            statusMessage = "Choose a name and keep the rectangle inside the screen."
            return
        }
        let layout = CustomWindowLayout(
            id: uuidProvider(),
            title: customTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            rect: customDraftRect
        )
        do {
            try customStore.save(layout)
            customLayouts = try customStore.load()
        } catch {
            statusMessage = error.localizedDescription
            return
        }
        source = .custom
        query = ""
        selectedID = "custom.\(layout.id.uuidString)"
        isEditingCustom = false
        statusMessage = "Custom layout saved."
    }

    func cancelCustomEditor() {
        isEditingCustom = false
        statusMessage = nil
    }

    func goBack() {
        onGoBack()
    }

    func handleEscape() -> Bool {
        if isEditingCustom {
            cancelCustomEditor()
            return true
        }
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func stop() {
        applyTask?.cancel()
        applyTask = nil
    }

    func flushApplyForTesting() async {
        await applyTask?.value
    }

    private var selectedCustomID: UUID? {
        guard source == .custom,
              let raw = selectedPreset?.id.removingPrefix("custom."),
              let id = UUID(uuidString: raw) else {
            return nil
        }
        return id
    }

    private func deleteSelectedCustom() {
        guard let id = selectedCustomID else { return }
        do {
            try customStore.delete(id: id)
            customLayouts = try customStore.load()
        } catch {
            statusMessage = error.localizedDescription
            showsActionsMenu = false
            return
        }
        refreshSelection()
        statusMessage = "Custom layout deleted."
        showsActionsMenu = false
    }

    private func refreshSelection() {
        selectedID = LauncherListSelection.resolvedID(
            in: filteredPresets,
            selectedID: selectedID,
            id: \.id
        )
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
