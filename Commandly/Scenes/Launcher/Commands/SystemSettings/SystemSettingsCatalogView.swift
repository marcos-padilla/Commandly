import DesignSystem
import SwiftUI

struct SystemSettingsCatalogView: View {
    @Bindable var viewModel: SystemSettingsViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Search macOS settings…",
            searchAccessibilityIdentifier: "system-settings-catalog-query",
            sidebarWidth: 305,
            searchFocusRequest: viewModel.searchFocusRequest,
            onBack: viewModel.goBack,
            onSubmit: viewModel.openSelected,
            onMoveSelection: viewModel.moveSelection,
            onEscape: { if !viewModel.handleEscape() { viewModel.goBack() } },
            filterControl: { EmptyView() },
            sidebar: { list },
            detail: { detail }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System Settings catalog")
        .onAppear { DispatchQueue.main.async { viewModel.requestSearchFocus() } }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if viewModel.items.isEmpty {
                        Text("No matching settings").foregroundStyle(.secondary).padding(density.spacing(.md))
                    }
                    ForEach(viewModel.items) { item in
                        Button { viewModel.select(item.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: item.systemImage).frame(width: 22).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).commandlyFont(size: 12, weight: .medium)
                                    Text("Opens \(item.destinationTitle)").commandlyFont(size: 10).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(item.id == viewModel.selectedItem?.id ? LauncherPalette.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.title), opens \(item.destinationTitle)")
                        .accessibilityHint("Select, then press Return to open in System Settings.")
                        .accessibilityAddTraits(item.id == viewModel.selectedItem?.id ? .isSelected : [])
                        .id(item.id)
                    }
                }
                .padding(density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let item = viewModel.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: density.spacing(.md)) {
                    Image(systemName: item.systemImage).commandlyFont(size: 30, weight: .medium).foregroundStyle(.secondary)
                    Text(item.title).commandlyFont(size: 18, weight: .semibold).accessibilityAddTraits(.isHeader)
                    Text(item.subtitle).commandlyFont(size: 12, weight: .semibold)
                    Text(item.detail).commandlyFont(size: 12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        viewModel.openSelected()
                    } label: {
                        Label(viewModel.isOpening ? "Opening…" : "Open in System Settings", systemImage: "arrow.up.forward.app")
                    }
                    .disabled(!viewModel.canOpen)
                    .keyboardShortcut(.defaultAction)
                    Text("Choose and change options in macOS. Commandly only opens the settings page.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(density.spacing(.lg))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(item.id)
        } else {
            LauncherApplicationEmptyState(systemImage: "gearshape", title: "Find a settings page", message: "Try display, sound, keyboard, or privacy.")
        }
    }
}
