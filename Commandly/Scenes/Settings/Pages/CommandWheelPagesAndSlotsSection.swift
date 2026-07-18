import CommandKit
import DesignSystem
import SwiftUI

struct CommandWheelPagesAndSlotsSection: View {
    @Bindable var model: CommandWheelSettingsModel
    let profile: CommandWheelProfile
    let onChooseCommand: (Int) -> Void
    let onAddPage: (Int) -> Void
    let onOpenPermissions: () -> Void

    var body: some View {
        SettingsSection(
            "Pages and Slots",
            footer: "Each page keeps stable numbered slots. Choose a slot to assign content, edit its presentation, or move it without dragging."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                pageControls
                SettingsDivider(leadingInset: 0)
                HStack(alignment: .top, spacing: 18) {
                    CommandWheelRadialPreview(
                        slots: model.slotPresentations,
                        startAngleDegrees: profile.appearance.startAngleDegrees,
                        selectedSlotIndex: model.selectedSlotIndex,
                        onSelect: model.selectSlot
                    )
                    .frame(width: 280, height: 280)

                    VStack(alignment: .leading, spacing: 10) {
                        slotList
                        if let slot = selectedSlot {
                            CommandWheelSlotInspector(
                                model: model,
                                profile: profile,
                                slot: slot,
                                onChooseCommand: onChooseCommand,
                                onAddPage: onAddPage,
                                onOpenPermissions: onOpenPermissions
                            )
                            .id(slot.id)
                        } else {
                            Text("Select a numbered slot to edit it.")
                                .commandlyFont(size: 10.5)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.vertical, 8)
        }
    }

    private var pageControls: some View {
        HStack(spacing: 8) {
            Text("Page")
                .commandlyFont(size: 12.5, weight: .medium)
            Picker("Page", selection: pageSelection) {
                ForEach(profile.pages) { page in
                    Text(page.name).tag(page.id)
                }
            }
            .labelsHidden()
            .frame(width: 220)

            if let page = model.selectedPage {
                CommandWheelPageNameEditor(model: model, page: page)
                    .id(page.id)
            }

            Spacer()

            if let page = model.selectedPage, page.id != profile.rootPageID {
                Button("Delete Page", role: .destructive) {
                    Task {
                        await model.perform { try await model.deletePage(page.id) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("command-wheel.page.delete")
            }
        }
    }

    private var pageSelection: Binding<UUID> {
        Binding(
            get: { model.selectedPageID ?? profile.rootPageID },
            set: model.selectPage
        )
    }

    private var slotSelection: Binding<CommandWheelSlotID?> {
        Binding(
            get: { selectedSlot?.id },
            set: { value in
                if let value { model.selectSlot(value.slotIndex) }
            }
        )
    }

    private var selectedSlot: CommandWheelSlotPresentation? {
        guard let selectedSlotIndex = model.selectedSlotIndex else { return nil }
        return model.slotPresentations.first(where: { $0.id.slotIndex == selectedSlotIndex })
    }

    private var slotList: some View {
        List(selection: slotSelection) {
            ForEach(model.slotPresentations) { slot in
                CommandWheelSlotRow(slot: slot)
                    .tag(slot.id)
                    .accessibilityIdentifier(
                        "command-wheel.slot.\(slot.id.profileID.uuidString).\(slot.id.pageID.uuidString).\(slot.id.slotIndex)"
                    )
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 170, maxHeight: 210)
        .accessibilityLabel("Command Wheel slots")
    }
}

private struct CommandWheelPageNameEditor: View {
    @Bindable var model: CommandWheelSettingsModel
    let page: CommandWheelPage
    @State private var name: String

    init(model: CommandWheelSettingsModel, page: CommandWheelPage) {
        self.model = model
        self.page = page
        _name = State(initialValue: page.name)
    }

    var body: some View {
        HStack(spacing: 5) {
            TextField("Page name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit(save)
                .accessibilityIdentifier("command-wheel.page.name")
            Button("Save", action: save)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(name == page.name)
        }
    }

    private func save() {
        Task {
            await model.perform { try await model.renamePage(page.id, to: name) }
        }
    }
}

private struct CommandWheelSlotRow: View {
    let slot: CommandWheelSlotPresentation

    var body: some View {
        HStack(spacing: 8) {
            Text("\(slot.id.slotIndex + 1)")
                .commandlyFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            CommandWheelSettingsSlotIcon(slot: slot, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title)
                    .commandlyFont(size: 11.5, weight: .medium)
                    .lineLimit(1)
                if let subtitle = slot.subtitle {
                    Text(subtitle)
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            availabilityIndicator
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slot \(slot.id.slotIndex + 1), \(slot.title)")
    }

    @ViewBuilder
    private var availabilityIndicator: some View {
        switch slot.availability {
        case .empty:
            EmptyView()
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .missing:
            Image(systemName: "questionmark.diamond.fill")
                .foregroundStyle(.red)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct CommandWheelSlotInspector: View {
    @Bindable var model: CommandWheelSettingsModel
    let profile: CommandWheelProfile
    let slot: CommandWheelSlotPresentation
    let onChooseCommand: (Int) -> Void
    let onAddPage: (Int) -> Void
    let onOpenPermissions: () -> Void

    @State private var customLabel = ""
    @State private var customIcon = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Slot \(slot.id.slotIndex + 1)")
                    .commandlyFont(size: 12.5, weight: .semibold)
                Spacer()
                slotActions
            }

            if case .unavailable(let requiresPermission) = slot.availability {
                HStack {
                    Label(
                        requiresPermission
                            ? "This command needs permission before it can run."
                            : "This command is currently unavailable.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(.orange)
                    Spacer()
                    if requiresPermission {
                        Button("Open Permissions", action: onOpenPermissions)
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                }
            } else if slot.availability == .missing {
                Label(
                    "The saved command or provider is not installed. You can replace or clear it.",
                    systemImage: "questionmark.diamond.fill"
                )
                .commandlyFont(size: 9.5)
                .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                TextField("Custom label", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("SF Symbol", text: $customIcon)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button("Apply") { savePresentation() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if case .submenu(let pageID) = slot.content {
                Button("Open Submenu Page") { model.selectPage(pageID) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if case .command(let reference) = slot.content,
               let manifest = model.commandPicker.manifest(for: reference.commandID),
               manifest.arguments.isEmpty == false {
                Divider()
                Text("Command Arguments")
                    .commandlyFont(size: 10.5, weight: .semibold)
                ForEach(manifest.arguments, id: \.name) { argument in
                    CommandWheelArgumentEditor(
                        model: model,
                        argument: argument,
                        slotIndex: slot.id.slotIndex
                    )
                    .id("\(slot.id.slotIndex)-\(argument.name)")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsVisualStyle.fieldBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SettingsVisualStyle.separator, lineWidth: 1)
                }
        )
        .onAppear { refreshPresentationFields() }
        .accessibilityIdentifier("command-wheel.slot.inspector")
    }

    private var slotActions: some View {
        Menu("Slot Actions") {
            Button("Choose Command…") { onChooseCommand(slot.id.slotIndex) }
            Button("Add Submenu Page…") { onAddPage(slot.id.slotIndex) }
                .disabled(slot.availability != .empty)
            Menu("Dynamic Content") {
                Button("Recent Commands") { assignDynamic(CommandWheelDynamicProviderID.recentCommands) }
                Button("Frequent Commands") { assignDynamic(CommandWheelDynamicProviderID.frequentCommands) }
            }
            .disabled(slot.availability != .empty)
            Divider()
            Button("Move Earlier") { move(.earlier) }
                .disabled(slot.id.slotIndex == 0 || slot.availability == .empty)
            Button("Move Later") { move(.later) }
                .disabled(
                    slot.id.slotIndex + 1 >= profile.interaction.visibleSlotCount
                        || slot.availability == .empty
                )
            Button("Clear Slot", role: .destructive) { clear() }
                .disabled(slot.availability == .empty)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .accessibilityLabel("Actions for slot \(slot.id.slotIndex + 1)")
    }

    private func refreshPresentationFields() {
        guard let segment = model.selectedPage?.segments.first(where: {
            $0.slotIndex == slot.id.slotIndex
        }) else { return }
        customLabel = segment.customLabel ?? ""
        customIcon = segment.customIcon?.systemSymbolName ?? ""
    }

    private func savePresentation() {
        Task {
            await model.perform {
                try await model.setSegmentPresentation(
                    label: customLabel,
                    systemSymbol: customIcon,
                    slotIndex: slot.id.slotIndex
                )
            }
        }
    }

    private func assignDynamic(_ providerID: String) {
        Task {
            await model.perform {
                try await model.assignDynamicProvider(
                    providerID,
                    to: slot.id.slotIndex,
                    replacing: false
                )
            }
        }
    }

    private func move(_ direction: CommandWheelMoveDirection) {
        Task {
            await model.perform {
                try await model.moveSlot(slot.id.slotIndex, direction: direction)
            }
        }
    }

    private func clear() {
        Task {
            await model.perform { try await model.clearSlot(slot.id.slotIndex) }
        }
    }
}

private struct CommandWheelArgumentEditor: View {
    @Bindable var model: CommandWheelSettingsModel
    let argument: CommandArgument
    let slotIndex: Int
    @State private var draft: String

    init(
        model: CommandWheelSettingsModel,
        argument: CommandArgument,
        slotIndex: Int
    ) {
        self.model = model
        self.argument = argument
        self.slotIndex = slotIndex
        _draft = State(initialValue: Self.text(model.argumentValue(argument, slotIndex: slotIndex)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(argument.name)
                    .commandlyFont(size: 10.5, weight: .medium)
                if argument.isRequired {
                    Text("REQUIRED")
                        .commandlyFont(size: 7.5, weight: .bold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if argument.valueType == .boolean {
                    Toggle("", isOn: booleanBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                } else {
                    TextField(argument.description, text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                        .onSubmit(save)
                    Button("Set", action: save)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text(argument.description)
                .commandlyFont(size: 9)
                .foregroundStyle(.tertiary)
        }
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: {
                guard case .boolean(let value) = model.argumentValue(
                    argument,
                    slotIndex: slotIndex
                ) else { return false }
                return value
            },
            set: { value in
                Task {
                    await model.perform {
                        try await model.setArgumentValue(
                            .boolean(value),
                            argument: argument,
                            slotIndex: slotIndex
                        )
                    }
                }
            }
        )
    }

    private func save() {
        Task {
            await model.perform {
                try await model.setArgumentText(
                    draft,
                    argument: argument,
                    slotIndex: slotIndex
                )
            }
        }
    }

    private nonisolated static func text(_ value: CommandArgumentValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let value): return value
        case .boolean(let value): return String(value)
        case .integer(let value): return String(value)
        case .decimal(let value): return String(value)
        case .url(let value): return value.absoluteString
        case .stringList(let values): return values.joined(separator: "\n")
        }
    }
}

private struct CommandWheelRadialPreview: View {
    let slots: [CommandWheelSlotPresentation]
    let startAngleDegrees: Double
    let selectedSlotIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let layout = CommandWheelSegmentLayout(
                wheelRadius: max(80, (side - 8) / 2),
                slotCount: slots.count
            )
            ZStack {
                Circle()
                    .fill(SettingsVisualStyle.fieldBackground.opacity(0.7))
                    .overlay {
                        Circle().stroke(SettingsVisualStyle.separator, lineWidth: 1)
                    }
                    .frame(width: side - 8, height: side - 8)
                    .position(center)

                Circle()
                    .fill(.secondary.opacity(0.08))
                    .frame(width: layout.centerDiameter, height: layout.centerDiameter)
                    .position(center)
                    .accessibilityHidden(true)

                ForEach(slots) { slot in
                    let offset = layout.offset(
                        slotIndex: slot.id.slotIndex,
                        startAngleDegrees: startAngleDegrees
                    )
                    Button {
                        onSelect(slot.id.slotIndex)
                    } label: {
                        CommandWheelSettingsSlotIcon(
                            slot: slot,
                            size: layout.primaryIconSize
                        )
                        .frame(width: layout.tileSide, height: layout.tileSide)
                        .overlay(alignment: .topLeading) {
                            if layout.showsKeyboardHint {
                                Text("\(slot.id.slotIndex + 1)")
                                    .commandlyFont(
                                        size: max(6, layout.badgeSize * 0.64),
                                        weight: .bold,
                                        design: .monospaced
                                    )
                                    .frame(width: layout.badgeSize, height: layout.badgeSize)
                                    .background(.thinMaterial, in: Circle())
                                    .padding(layout.badgeInset)
                            }
                        }
                        .background(
                            Circle().fill(
                                selectedSlotIndex == slot.id.slotIndex
                                    ? Color.accentColor.opacity(0.24)
                                    : SettingsVisualStyle.detailBackground
                            )
                        )
                        .overlay {
                            Circle().stroke(
                                selectedSlotIndex == slot.id.slotIndex
                                    ? Color.accentColor
                                    : SettingsVisualStyle.separator,
                                lineWidth: selectedSlotIndex == slot.id.slotIndex ? 2 : 1
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: center.x + offset.width,
                        y: center.y + offset.height
                    )
                    .accessibilityLabel("Slot \(slot.id.slotIndex + 1), \(slot.title)")
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live Command Wheel preview")
    }
}

private struct CommandWheelSettingsSlotIcon: View {
    let slot: CommandWheelSlotPresentation
    let size: CGFloat

    var body: some View {
        if slot.usesCustomIcon == false, let path = slot.applicationIconPath {
            ApplicationLauncherIcon(path: path, size: size)
        } else {
            Image(systemName: slot.systemImage)
                .font(.system(size: size, weight: .semibold))
        }
    }
}
