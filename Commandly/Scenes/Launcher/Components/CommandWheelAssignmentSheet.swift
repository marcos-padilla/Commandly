import CommandKit
import DesignSystem
import SwiftUI

/// Item-driven launcher sheet for placing one exact command reference in Command Wheel.
struct CommandWheelAssignmentSheet: View {
    @Bindable var model: CommandWheelAssignmentModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg.rawValue) {
                    destinationSection
                    existingAssignmentsSection
                    submenuSection
                }
                .padding(Spacing.lg.rawValue)
            }
            Divider()
            footer
        }
        .frame(width: 610, height: 610)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add \(model.commandTitle) to Command Wheel")
        .accessibilityIdentifier("command-wheel-assignment-sheet")
        .confirmationDialog(
            model.pendingAction?.title ?? "Confirm Command Wheel change",
            isPresented: pendingConfirmationBinding,
            presenting: model.pendingAction
        ) { action in
            Button(action.confirmationTitle, role: .destructive) {
                Task { @MainActor in
                    let completed = await model.confirmPendingAction(action)
                    if completed, action.dismissesSheetAfterConfirmation {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingAction()
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            Image(systemName: model.commandSystemImage)
                .commandlyFont(size: 20, weight: .semibold)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add to Command Wheel…")
                    .commandlyFont(size: 16, weight: .semibold)
                Text(model.commandTitle)
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("command-wheel-assignment-cancel")
        }
        .padding(Spacing.lg.rawValue)
    }

    private var destinationSection: some View {
        assignmentGroup(title: "Destination") {
            Grid(alignment: .leading, horizontalSpacing: Spacing.md.rawValue, verticalSpacing: 10) {
                GridRow {
                    Text("Profile")
                        .foregroundStyle(.secondary)
                    Picker("Profile", selection: profileSelection) {
                        ForEach(model.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("command-wheel-assignment-profile")
                }
                GridRow {
                    Text("Page")
                        .foregroundStyle(.secondary)
                    Picker("Page", selection: pageSelection) {
                        ForEach(model.pages) { page in
                            Text(page.name).tag(page.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("command-wheel-assignment-page")
                }
                GridRow {
                    Text("Slot")
                        .foregroundStyle(.secondary)
                    Picker("Slot", selection: slotSelection) {
                        ForEach(model.slots) { slot in
                            Text("\(slot.title) — \(slot.detail)").tag(slot.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("command-wheel-assignment-slot")
                }
            }
            .commandlyFont(size: 12)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs.rawValue) {
                Image(systemName: model.selectedSlotIsOccupied
                    ? "exclamationmark.circle.fill"
                    : "checkmark.circle.fill")
                    .foregroundStyle(model.selectedSlotIsOccupied ? Color.orange : Color.green)
                    .accessibilityHidden(true)
                Text(model.selectedSlotDescription)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("command-wheel-assignment-occupancy")
        }
    }

    private var existingAssignmentsSection: some View {
        assignmentGroup(title: "Existing assignments") {
            if model.existingAssignments.isEmpty {
                Text("This exact command and its saved arguments are not assigned yet.")
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Spacing.xs.rawValue) {
                    ForEach(model.existingAssignments) { assignment in
                        existingAssignmentRow(assignment)
                    }
                }
            }
        }
    }

    private var submenuSection: some View {
        assignmentGroup(title: "Add inside a new submenu") {
            Text("Create a submenu in the selected destination and place this command inside it in one saved change.")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.sm.rawValue) {
                TextField("Submenu name", text: $model.newSubmenuName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("New submenu name")
                    .accessibilityIdentifier("command-wheel-assignment-submenu-name")

                Picker("Child slot", selection: $model.newSubmenuChildSlotIndex) {
                    ForEach(model.childSlots) { slot in
                        Text(slot.title).tag(slot.id)
                    }
                }
                .frame(width: 130)
                .accessibilityIdentifier("command-wheel-assignment-submenu-child-slot")

                Button(model.selectedSlotIsOccupied ? "Replace with Submenu…" : "Create Submenu") {
                    Task { @MainActor in
                        if await model.requestNewSubmenu() {
                            dismiss()
                        }
                    }
                }
                .disabled(model.isSaving)
                .accessibilityIdentifier("command-wheel-assignment-create-submenu")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityIdentifier("command-wheel-assignment-error")
            }
            Spacer(minLength: 0)
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving Command Wheel assignment")
            }
            Button(model.selectedSlotIsOccupied ? "Replace…" : "Add") {
                Task { @MainActor in
                    if await model.requestAssignment() {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isSaving)
            .accessibilityIdentifier("command-wheel-assignment-confirm")
        }
        .padding(Spacing.lg.rawValue)
    }

    private func existingAssignmentRow(
        _ assignment: CommandWheelExistingAssignment
    ) -> some View {
        HStack(spacing: Spacing.sm.rawValue) {
            Image(systemName: "circle.grid.cross")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(assignment.locationDescription)
                .commandlyFont(size: 12, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm.rawValue)
            Button("Reveal") {
                model.reveal(assignment)
                dismiss()
            }
            .accessibilityLabel("Reveal \(assignment.locationDescription) in Command Wheel Settings")
            .accessibilityIdentifier("command-wheel-assignment-reveal-\(assignment.id.uuidString)")
            Button("Move Here") {
                Task { @MainActor in
                    if await model.requestMove(from: assignment.location) {
                        dismiss()
                    }
                }
            }
            .disabled(model.isSaving || assignment.location == model.selectedLocation)
            .accessibilityLabel("Move \(assignment.locationDescription) to selected slot")
            .accessibilityIdentifier("command-wheel-assignment-move-\(assignment.id.uuidString)")
            Button("Remove", role: .destructive) {
                model.requestRemoval(of: assignment)
            }
            .disabled(model.isSaving)
            .accessibilityLabel("Remove \(assignment.locationDescription)")
            .accessibilityIdentifier("command-wheel-assignment-remove-\(assignment.id.uuidString)")
        }
        .padding(.horizontal, Spacing.sm.rawValue)
        .padding(.vertical, Spacing.xs.rawValue)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-wheel-assignment-existing-\(assignment.id.uuidString)")
    }

    private func assignmentGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
            Text(title)
                .commandlyFont(size: 12, weight: .semibold)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var profileSelection: Binding<UUID> {
        Binding(
            get: { model.selectedProfileID },
            set: { model.selectProfile($0) }
        )
    }

    private var pageSelection: Binding<UUID> {
        Binding(
            get: { model.selectedPageID },
            set: { model.selectPage($0) }
        )
    }

    private var slotSelection: Binding<Int> {
        Binding(
            get: { model.selectedSlotIndex },
            set: { model.selectSlot($0) }
        )
    }

    private var pendingConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingAction != nil },
            set: { isPresented in
                if isPresented == false {
                    model.cancelPendingAction()
                }
            }
        )
    }
}

private extension CommandWheelAssignmentPendingAction {
    var dismissesSheetAfterConfirmation: Bool {
        switch self {
        case .remove: return false
        case .replaceAssignment, .replaceMove, .replaceWithSubmenu: return true
        }
    }
}

#Preview("Command Wheel assignment") {
    let configuration = CommandWheelDefaults.configuration
    let store = CommandWheelProfileStore(
        repository: InMemoryCommandWheelProfileRepository(configuration: configuration),
        initialConfiguration: configuration
    )
    let model = CommandWheelAssignmentModel(
        reference: BuiltInCommandReference.openInstalledApplication(
            bundleIdentifier: "com.example.Preview"
        ),
        commandTitle: "Preview Application",
        commandSystemImage: "app.fill",
        store: store,
        reportStatus: { _ in },
        revealAssignment: { _ in }
    )
    Group {
        if let model {
            CommandWheelAssignmentSheet(model: model)
        } else {
            Text("Preview unavailable")
        }
    }
}
