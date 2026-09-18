import AppKit
import DesignSystem
import Infrastructure
import SwiftUI

struct WindowSwitcherView: View {
    @Bindable var model: WindowSwitcherPresentationModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            footer
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : .clear)
                .background(
                    reduceTransparency ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 26, y: 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commandly Window Switcher")
    }

    private var header: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            Image(systemName: model.context.isDockPreview ? "dock.rectangle" : "macwindow.on.rectangle")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if model.configuration.allowsSearch {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(model.query.isEmpty ? "Type to filter windows" : model.query)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(model.query.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if model.query.isEmpty == false {
                        Button {
                            model.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear window search")
                        .accessibilityLabel("Clear window search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    model.query.isEmpty ? "Window search, empty" : "Window search, \(model.query)"
                )
            } else {
                Text(model.context.isDockPreview ? "Application Windows" : "Window Switcher")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text(model.searchSummary)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            if model.context.isDockPreview {
                Button {
                    model.isPinned.toggle()
                } label: {
                    Image(systemName: model.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help(model.isPinned ? "Unpin preview" : "Keep preview open")
                .accessibilityLabel(model.isPinned ? "Unpin Dock preview" : "Pin Dock preview")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding windows…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .empty:
            unavailable(
                title: model.query.isEmpty ? "No windows available" : "No matching windows",
                symbol: "macwindow.badge.plus",
                description: model.query.isEmpty
                    ? "Open a window or broaden the Window Set settings."
                    : "Try a different application or window title."
            )
        case .failed(let message):
            unavailable(
                title: "Window access unavailable",
                symbol: "accessibility",
                description: message
            )
        case .ready:
            if model.visibleWindows.isEmpty {
                unavailable(
                    title: "No matching windows",
                    symbol: "magnifyingglass",
                    description: "Try a different application or window title."
                )
            } else {
                windowCollection
            }
        }
    }

    @ViewBuilder
    private var windowCollection: some View {
        switch model.configuration.layoutStyle {
        case .grid:
            ScrollView {
                if usesApplicationGroups {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.applicationGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                applicationGroupHeader(group)
                                LazyVGrid(columns: gridColumns, spacing: 10) {
                                    ForEach(group.windows) { window in
                                        WindowSwitcherCard(
                                            model: model,
                                            window: window,
                                            style: .grid
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(model.visibleWindows) { window in
                            WindowSwitcherCard(model: model, window: window, style: .grid)
                        }
                    }
                    .padding(12)
                }
            }
        case .list:
            ScrollView {
                LazyVStack(spacing: 4) {
                    if usesApplicationGroups {
                        ForEach(model.applicationGroups) { group in
                            VStack(spacing: 4) {
                                applicationGroupHeader(group)
                                    .padding(.top, 6)
                                ForEach(group.windows) { window in
                                    WindowSwitcherCard(model: model, window: window, style: .list)
                                }
                            }
                        }
                    } else {
                        ForEach(model.visibleWindows) { window in
                            WindowSwitcherCard(model: model, window: window, style: .list)
                        }
                    }
                }
                .padding(10)
            }
        case .strip:
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    if usesApplicationGroups {
                        ForEach(model.applicationGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                applicationGroupHeader(group)
                                HStack(spacing: 10) {
                                    ForEach(group.windows) { window in
                                        WindowSwitcherCard(
                                            model: model,
                                            window: window,
                                            style: .strip
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        ForEach(model.visibleWindows) { window in
                            WindowSwitcherCard(model: model, window: window, style: .strip)
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var usesApplicationGroups: Bool {
        model.configuration.filterMode == .applications
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: model.configuration.gridColumnCount
        )
    }

    private func applicationGroupHeader(
        _ group: WindowSwitcherApplicationGroup
    ) -> some View {
        HStack(spacing: 7) {
            if let icon = NSRunningApplication(
                processIdentifier: group.processIdentifier
            )?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)
            }
            Text(group.applicationName)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
            Text("\(group.windows.count)")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(group.applicationName), \(group.windows.count) "
                + (group.windows.count == 1 ? "window" : "windows")
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let message = model.statusMessage {
                Label(message, systemImage: "info.circle")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                keyboardHint("Tab", "Next")
                keyboardHint("⇧Tab", "Previous")
                keyboardHint("↩", "Open")
                keyboardHint("Esc", "Cancel")
            }
            Spacer(minLength: 0)
            if let window = model.selectedWindow {
                Text(window.applicationName)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private func keyboardHint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            Text(title).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func unavailable(title: String, symbol: String, description: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private enum WindowSwitcherCardStyle: Equatable {
    case grid
    case list
    case strip
}

private struct WindowSwitcherCard: View {
    @Bindable var model: WindowSwitcherPresentationModel
    let window: WindowSnapshot
    let style: WindowSwitcherCardStyle
    @State private var isHovered = false

    private var isSelected: Bool { model.selectedID == window.id }

    var body: some View {
        Group {
            if style == .list {
                listContent
            } else {
                previewContent
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.14 : 0.07),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering, model.configuration.allowsMouseSelection {
                model.select(window.id)
            }
        }
        .onTapGesture {
            model.select(window.id)
            model.activateSelection()
        }
        .contextMenu { actionMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open Window") {
            model.select(window.id)
            model.activateSelection()
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                thumbnail
                if model.configuration.showsWindowActions, isHovered || isSelected {
                    actionButtons
                        .padding(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                stateBadge
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            labels
        }
        .padding(8)
        .frame(width: cardWidth)
    }

    private var listContent: some View {
        HStack(spacing: 10) {
            applicationIcon(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                if model.configuration.showsWindowTitles {
                    Text(window.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                if model.configuration.showsApplicationNames {
                    Text(window.applicationName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            stateBadge
            if model.configuration.showsWindowActions, isHovered || isSelected {
                actionButtons
            }
        }
        .padding(.horizontal, 10)
        .frame(height: listHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = model.thumbnails[window.id] {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.primary.opacity(0.055), Color.primary.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                applicationIcon(size: iconSize)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.configuration.showsWindowTitles {
                Text(window.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if model.configuration.showsApplicationNames {
                Text(window.applicationName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stateBadge: some View {
        if window.isWindowless {
            badge("No Windows", systemImage: "app.dashed")
        } else if window.isMinimized {
            badge("Minimized", systemImage: "minus.rectangle")
        } else if window.isHidden {
            badge("Hidden", systemImage: "eye.slash")
        }
    }

    private func badge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 8.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(title)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if window.isWindowless == false {
                actionButton(
                    window.isMinimized ? "Restore" : "Minimize",
                    symbol: window.isMinimized ? "arrow.up.left.and.arrow.down.right" : "minus",
                    action: .toggleMinimized
                )
                actionButton(
                    "Full Screen",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    action: .toggleFullScreen
                )
                actionButton("Close", symbol: "xmark", action: .close)
            }
            Menu {
                actionMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9.5, weight: .bold))
                    .frame(width: 21, height: 21)
                    .background(.thinMaterial, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More window actions")
            .accessibilityLabel("More actions for \(window.title)")
        }
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        action: WindowAction
    ) -> some View {
        Button {
            model.select(window.id)
            model.perform(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .frame(width: 21, height: 21)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel("\(title) \(window.title)")
    }

    @ViewBuilder
    private var actionMenu: some View {
        Button(window.isWindowless ? "Open Application" : "Open Window") {
            perform(.activate, dismiss: true)
        }
        if window.isWindowless == false {
            Divider()
            Button(window.isMinimized ? "Restore" : "Minimize") { perform(.toggleMinimized) }
            Button("Toggle Full Screen") { perform(.toggleFullScreen) }
            Button("Zoom") { perform(.zoom) }
            Button("Center") { perform(.center) }
            Menu("Arrange") {
                Button("Left Half") { perform(.leftHalf) }
                Button("Right Half") { perform(.rightHalf) }
                Button("Top Half") { perform(.topHalf) }
                Button("Bottom Half") { perform(.bottomHalf) }
            }
            Divider()
            Button("Close Window", role: .destructive) { perform(.close) }
        }
        Button("Quit \(window.applicationName)", role: .destructive) { perform(.quit) }
    }

    private func perform(_ action: WindowAction, dismiss: Bool = false) {
        model.select(window.id)
        model.perform(action, dismissAfterSuccess: dismiss)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(isHovered ? 0.055 : 0.025))
    }

    @ViewBuilder
    private func applicationIcon(size: CGFloat) -> some View {
        if let application = NSRunningApplication(processIdentifier: window.processIdentifier),
           let icon = application.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.72))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private var cardWidth: CGFloat {
        switch model.configuration.itemSize {
        case .compact: 176
        case .regular: 224
        case .large: 286
        }
    }

    private var iconSize: CGFloat {
        switch model.configuration.itemSize {
        case .compact: 42
        case .regular: 56
        case .large: 70
        }
    }

    private var listHeight: CGFloat {
        switch model.configuration.itemSize {
        case .compact: 42
        case .regular: 50
        case .large: 60
        }
    }

    private var accessibilityLabel: String {
        var components = [window.applicationName, window.title]
        if window.isMinimized { components.append("minimized") }
        if window.isHidden { components.append("hidden") }
        if window.isWindowless { components.append("no open windows") }
        return components.joined(separator: ", ")
    }
}
