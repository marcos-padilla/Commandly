import AppKit
import Infrastructure
import SwiftUI

/// Native keyboard-first launcher content; the application wrapper supplies navigation and authenticated services.
public struct AppMenusView: View {
    @Bindable private var model: AppMenusModel
    private let goBack: () -> Void
    @FocusState private var searchFocused: Bool
    public init(model: AppMenusModel, goBack: @escaping () -> Void) { self.model = model; self.goBack = goBack }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { model.stop(); goBack() }) { Image(systemName: "chevron.left") }.accessibilityLabel("Back")
                Text("App Menus").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Read Menus", action: model.readMenus).disabled(model.isWorking)
                Menu("Access") {
                    Button("Enable App Menus", action: model.enable)
                    Button("Disable App Menus", action: model.disable)
                }.disabled(model.isWorking)
            }.padding(12)
            Text("Read the current app’s accessible menu only when requested. Invoking a menu command can change that app’s data. Favorites store identity hashes, never captured menu titles.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
            HStack {
                TextField("Search current app commands", text: $model.query).focused($searchFocused)
                    .textFieldStyle(.roundedBorder).onSubmit(model.invokeSelection)
                Toggle("Favorites", isOn: $model.favoritesOnly).toggleStyle(.button)
            }.padding(.horizontal, 12)
            if model.isWorking { ProgressView().controlSize(.small).padding(8) }
            if let message = model.recoveryMessage { Text(message).font(.callout).padding(12).accessibilityLabel(message) }
            List(selection: $model.selection) {
                ForEach(model.filteredItems) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title).foregroundStyle(item.enabled ? .primary : .secondary)
                            Text(item.ancestors.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.toggleFavorite(item) } label: {
                            Image(systemName: model.favorites.contains(item.identity) ? "star.fill" : "star")
                        }.buttonStyle(.borderless).disabled(model.isSavingFavorite || !model.favoritesLoaded)
                            .accessibilityLabel(model.favorites.contains(item.identity) ? "Remove favorite" : "Favorite command")
                    }.tag(item.handle)
                }
            }.overlay { if model.state == .ready && model.filteredItems.isEmpty { Text("No matching commands").foregroundStyle(.secondary) } }
            HStack {
                Text(model.bundleIdentifier.isEmpty ? "No menu captured" : model.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Invoke Selected", action: model.invokeSelection).keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.state != .ready || !model.filteredItems.contains { $0.handle == model.selection && $0.enabled })
            }.padding(12)
        }
        .frame(minWidth: 480, minHeight: 320)
        .task { model.open(); searchFocused = true }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.stop() }
        .onChange(of: model.query) { _, _ in model.selection = model.filteredItems.first?.handle }
        .onChange(of: model.favoritesOnly) { _, _ in model.selection = model.filteredItems.first?.handle }
        .accessibilityElement(children: .contain).accessibilityLabel("Current app menu commands")
    }
}
