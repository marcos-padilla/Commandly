import DesignSystem
import SecurityKit
import SwiftUI
import UniformTypeIdentifiers

struct CommandWheelSettingsPage: View {
    @Bindable var model: CommandWheelSettingsModel
    let permissionState: PermissionState
    let onOpenPermissions: () -> Void

    @State private var presentedSheet: CommandWheelSettingsSheet?
    @State private var exportDocument: CommandWheelProfileDocument?
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportFilename = "Commandly Command Wheel Profiles"
    private let importReader = CommandWheelProfileImportReader()

    var body: some View {
        HStack(spacing: 0) {
            CommandWheelProfileSidebar(
                model: model,
                onImport: { isImporterPresented = true },
                onExport: prepareExport
            )
            .frame(minWidth: 218, idealWidth: 232, maxWidth: 248)

            Divider()
                .overlay(SettingsVisualStyle.separator)

            CommandWheelProfileEditor(
                model: model,
                onChooseCommand: { slotIndex in
                    presentedSheet = .commandPicker(slotIndex: slotIndex)
                },
                onAddPage: { slotIndex in
                    presentedSheet = .addPage(slotIndex: slotIndex)
                },
                permissionState: permissionState,
                onOpenPermissions: onOpenPermissions
            )
        }
        .background(SettingsVisualStyle.detailBackground)
        .task { await model.load() }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .commandPicker(let slotIndex):
                CommandWheelCommandPickerSheet(
                    settingsModel: model,
                    slotIndex: slotIndex
                )
            case .addPage(let slotIndex):
                CommandWheelAddPageSheet(
                    model: model,
                    slotIndex: slotIndex
                )
            }
        }
        .alert(item: $model.pendingReplacement) { pending in
            Alert(
                title: Text("Replace occupied slot?"),
                message: Text(
                    "Slot \(pending.destination.slotIndex + 1) already contains an item. Replace it with \(pending.title)?"
                ),
                primaryButton: .destructive(Text("Replace")) {
                    Task {
                        await model.perform {
                            try await model.confirmPendingReplacement()
                        }
                    }
                },
                secondaryButton: .cancel {
                    model.cancelPendingReplacement()
                }
            )
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                model.statusMessage = "Exported Command Wheel profiles."
            case .failure:
                model.errorMessage = "Command Wheel profiles could not be exported."
            }
        }
    }

    private func prepareExport(_ profileIDs: Set<UUID>?) {
        Task {
            await model.perform {
                let data = try await model.exportProfiles(profileIDs)
                exportDocument = CommandWheelProfileDocument(data: data)
                if let profileID = profileIDs?.first,
                   let profile = model.profiles.first(where: { $0.id == profileID }) {
                    exportFilename = "Commandly \(safeFilename(profile.name)) Wheel"
                } else {
                    exportFilename = "Commandly Command Wheel Profiles"
                }
                isExporterPresented = true
            }
        }
    }

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await model.perform {
                    let data = try await importReader.read(url)
                    try await model.importProfiles(from: data)
                }
            }
        case .failure:
            model.errorMessage = "The selected Command Wheel file could not be opened."
        }
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:")
        return value.components(separatedBy: forbidden).joined(separator: "-")
    }
}

private enum CommandWheelSettingsSheet: Identifiable {
    case commandPicker(slotIndex: Int)
    case addPage(slotIndex: Int)

    var id: String {
        switch self {
        case .commandPicker(let slotIndex): return "command-\(slotIndex)"
        case .addPage(let slotIndex): return "page-\(slotIndex)"
        }
    }
}

private struct CommandWheelProfileSidebar: View {
    @Bindable var model: CommandWheelSettingsModel
    let onImport: () -> Void
    let onExport: (Set<UUID>?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Toggle(
                "Enable Command Wheel",
                isOn: Binding(
                    get: { model.configuration.isEnabled },
                    set: { enabled in
                        Task {
                            await model.perform {
                                try await model.setCommandWheelEnabled(enabled)
                            }
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .commandlyFont(size: 11.5, weight: .medium)
            .padding(.horizontal, Spacing.sm.rawValue)
            .frame(height: 46)
            .accessibilityIdentifier("command-wheel.enabled")

            Divider()
                .overlay(SettingsVisualStyle.separator)

            List(selection: profileSelection) {
                ForEach(model.profiles) { profile in
                    CommandWheelProfileRow(
                        profile: profile,
                        isDefault: profile.id == model.configuration.defaultProfileID,
                        onEnabledChange: { enabled in
                            Task {
                                await model.perform {
                                    try await model.setProfileEnabled(
                                        enabled,
                                        profileID: profile.id
                                    )
                                }
                            }
                        }
                    )
                    .tag(profile.id)
                    .listRowInsets(
                        EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 40)

            Divider()
                .overlay(SettingsVisualStyle.separator)

            profileActions
                .padding(8)
        }
        .background(SettingsVisualStyle.sidebarBackground.opacity(0.42))
    }

    private var profileSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedProfileID },
            set: { newValue in
                if let newValue { model.selectProfile(newValue) }
            }
        )
    }

    private var profileActions: some View {
        HStack(spacing: 5) {
            Button {
                Task {
                    await model.perform { try await model.createProfile() }
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("Create profile")
            .accessibilityLabel("Create Command Wheel profile")
            .accessibilityIdentifier("command-wheel.profile.add")

            Button {
                guard let profileID = model.selectedProfileID else { return }
                Task {
                    await model.perform { try await model.duplicateProfile(profileID) }
                }
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .help("Duplicate profile")
            .accessibilityLabel("Duplicate selected profile")
            .disabled(model.selectedProfileID == nil)

            Button {
                guard let profileID = model.selectedProfileID else { return }
                Task {
                    await model.perform { try await model.deleteProfile(profileID) }
                }
            } label: {
                Image(systemName: "minus")
            }
            .help("Delete profile")
            .accessibilityLabel("Delete selected profile")
            .disabled(cannotDeleteSelection)

            Spacer(minLength: 2)

            Menu {
                Button("Move Earlier") { moveSelected(.earlier) }
                Button("Move Later") { moveSelected(.later) }
                Divider()
                Button("Import Profiles…", action: onImport)
                Button("Export Selected…") {
                    if let selected = model.selectedProfileID { onExport([selected]) }
                }
                Button("Export All…") { onExport(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Profile actions")
            .accessibilityLabel("Command Wheel profile actions")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var cannotDeleteSelection: Bool {
        guard let selected = model.selectedProfileID else { return true }
        return model.profiles.count == 1
            || selected == model.configuration.defaultProfileID
    }

    private func moveSelected(_ direction: CommandWheelMoveDirection) {
        guard let profileID = model.selectedProfileID else { return }
        Task {
            await model.perform {
                try await model.moveProfile(profileID, direction: direction)
            }
        }
    }
}

private struct CommandWheelProfileRow: View {
    let profile: CommandWheelProfile
    let isDefault: Bool
    let onEnabledChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            settingsGlyph(
                isDefault ? "star.fill" : "circle.hexagongrid",
                emphasized: profile.isEnabled,
                size: 19
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .commandlyFont(size: 11.5, weight: .medium)
                    .lineLimit(1)
                Text(isDefault ? "Default profile" : "Wheel profile")
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 3)

            Toggle("", isOn: Binding(
                get: { profile.isEnabled },
                set: { enabled in onEnabledChange(enabled) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(isDefault)
            .accessibilityLabel("Enable \(profile.name)")
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-wheel.profile.\(profile.id.uuidString)")
    }
}
