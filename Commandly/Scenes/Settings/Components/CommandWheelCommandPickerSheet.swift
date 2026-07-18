import CommandKit
import DesignSystem
import SwiftUI

struct CommandWheelCommandPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var picker: CommandWheelCommandPickerModel
    let settingsModel: CommandWheelSettingsModel
    let slotIndex: Int

    init(settingsModel: CommandWheelSettingsModel, slotIndex: Int) {
        self.settingsModel = settingsModel
        self.slotIndex = slotIndex
        self.picker = settingsModel.commandPicker
    }

    var body: some View {
        NavigationStack {
            Group {
                if picker.options.isEmpty, picker.isSearching == false {
                    ContentUnavailableView(
                        "No commands found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another command name, alias, or keyword.")
                    )
                } else {
                    List(picker.options) { option in
                        Button {
                            choose(option)
                        } label: {
                            CommandWheelCommandOptionRow(option: option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            option.accessibilityIdentifier
                        )
                    }
                    .listStyle(.inset)
                }
            }
            .overlay(alignment: .top) {
                if picker.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                        .accessibilityLabel("Searching commands")
                }
            }
            .searchable(text: $picker.query, prompt: "Search commands and applications")
            .task(id: picker.query) { await picker.search() }
            .navigationTitle("Choose Command for Slot \(slotIndex + 1)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    private func choose(_ option: CommandWheelCommandOption) {
        Task {
            do {
                try await settingsModel.requestCommandAssignment(
                    option,
                    to: slotIndex
                )
                dismiss()
            } catch let error as any LocalizedError {
                settingsModel.errorMessage = error.errorDescription
                    ?? "The command could not be assigned."
            } catch {
                settingsModel.errorMessage = "The command could not be assigned."
            }
        }
    }
}

private struct CommandWheelCommandOptionRow: View {
    let option: CommandWheelCommandOption

    var body: some View {
        HStack(spacing: 10) {
            launcherItemIcon(
                icon: option.icon,
                emphasized: option.availability.isAvailable,
                size: 22
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .commandlyFont(size: 12.5, weight: .medium)
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if option.availability.isAvailable == false {
                Text("UNAVAILABLE")
                    .commandlyFont(size: 8.5, weight: .bold)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            option.availability.isAvailable ? "Available" : "Currently unavailable"
        )
    }
}

struct CommandWheelAddPageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CommandWheelSettingsModel
    let slotIndex: Int

    @State private var name = "Submenu"
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Page name", text: $name)
                    .focused($isNameFocused)
                    .accessibilityIdentifier("command-wheel.page.name")

                Text("The new page is attached to slot \(slotIndex + 1) on the current page.")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Add Submenu Page")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addPage() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.isBusy
                        )
                }
            }
        }
        .frame(width: 420, height: 220)
        .onAppear { isNameFocused = true }
    }

    private func addPage() {
        Task {
            do {
                try await model.addPage(
                    named: name,
                    from: slotIndex,
                    replacing: false
                )
                dismiss()
            } catch let error as any LocalizedError {
                model.errorMessage = error.errorDescription
                    ?? "The submenu page could not be added."
            } catch {
                model.errorMessage = "The submenu page could not be added."
            }
        }
    }
}
