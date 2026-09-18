import CommandKit
import DesignSystem
import SwiftUI

struct MenuBarShortcutsView: View {
    @Bindable var model: MenuBarShortcutsModel
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var searchFocused: Bool
    @State private var isAttached = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.sm)) {
                CommandlyBackButton(action: model.goBack)
                Image(systemName: "menubar.rectangle").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Find a tool to pin…", text: $model.query)
                    .textFieldStyle(.plain).commandlyFont(size: 15)
                    .accessibilityLabel("Search menu-bar shortcuts")
                    .accessibilityIdentifier("menu-bar-shortcuts.search")
                    .focused($searchFocused)
                    .onSubmit(model.toggleSelected)
                    .onMoveCommand { direction in
                        if direction == .up { model.moveSelection(offset: -1) }
                        if direction == .down { model.moveSelection(offset: 1) }
                    }
                Text("\(model.controller.pinnedIDs.count) / 8 pinned").commandlyFont(size: 11).foregroundStyle(.secondary)
            }.padding(density.spacing(.md))
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.filteredItems) { item in row(item) }
                            if model.filteredItems.isEmpty {
                                Text("No matching tools").commandlyFont(size: 13).foregroundStyle(.secondary).padding(24)
                            }
                        }.padding(8)
                    }
                    .onChange(of: model.selectedID) { _, id in if let id { reader.scrollTo(id, anchor: .center) } }
                }.frame(minWidth: 290, maxWidth: .infinity)
                Divider()
                details.frame(width: 265).padding(density.spacing(.md))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            isAttached = true; model.load()
            DispatchQueue.main.async { if isAttached { searchFocused = true } }
        }
        .onDisappear { isAttached = false }
        .onChange(of: model.controller.catalog) { model.reconcileSelection() }
        .onChange(of: model.controller.pinnedIDs) { model.reconcileSelection() }
        .onExitCommand(perform: model.goBack)
    }

    private func row(_ item: MenuBarShortcutItem) -> some View {
        let selected = item.id == model.selectedID
        let pinned = model.controller.pinnedIDs.contains(item.id)
        return Button { model.selectedID = item.id } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage).commandlyFont(size: 17).frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).commandlyFont(size: 13, weight: .medium).lineLimit(1)
                    Text(item.isEnabled ? item.subtitle : "Disabled or unavailable")
                        .commandlyFont(size: 11).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if pinned { Image(systemName: "pin.fill").commandlyFont(size: 11).foregroundStyle(.secondary).accessibilityHidden(true) }
            }.padding(10).contentShape(Rectangle())
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).id(item.id)
            .accessibilityLabel("\(item.title), \(pinned ? "pinned" : "not pinned")\(item.isEnabled ? "" : ", unavailable")")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                Text("Keep a tool nearby").commandlyFont(size: 20, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("Pin up to eight tools as their own menu-bar icons. Open an icon's menu to launch its tool or remove it.")
                    .commandlyFont(size: 13).foregroundStyle(.secondary)
                if model.controller.needsPreferenceReset {
                    Text("Saved shortcuts need recovery. Reset clears the unreadable list without changing any tool settings.")
                        .commandlyFont(size: 13)
                    Button("Reset Saved Shortcuts") { model.controller.resetInvalidPreferences(); model.reconcileSelection() }
                } else if let item = model.selectedItem {
                    Divider()
                    Label(item.title, systemImage: item.systemImage).commandlyFont(size: 15, weight: .semibold)
                    Text(item.subtitle).commandlyFont(size: 12).foregroundStyle(.secondary)
                    Button(model.isSelectedPinned ? "Remove from Menu Bar" : "Pin to Menu Bar", action: model.toggleSelected)
                        .buttonStyle(.borderedProminent).disabled(!model.canToggle)
                        .accessibilityIdentifier("menu-bar-shortcuts.toggle")
                    if !item.isEnabled {
                        Text("Enable the application in Settings to use this shortcut. A saved pin can still be removed here.")
                            .commandlyFont(size: 12).foregroundStyle(.secondary)
                    }
                }
                Text("Hold Command while dragging icons to arrange them. macOS controls the space available beside the clock.")
                    .commandlyFont(size: 11).foregroundStyle(.secondary)
                Text("Pinned tools use their usual review and permission flows. Pinning never runs a tool.")
                    .commandlyFont(size: 11).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
