import CommandKit
import DesignSystem
import SwiftUI

struct ProductivityLibraryView: View {
    @Bindable var viewModel: ProductivityLibraryViewModel
    @Environment(\.commandlyLayoutDensity) private var density
    @State private var searchFocusRequest = 0

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Search your library…",
            searchAccessibilityIdentifier: "productivity-library-query",
            sidebarWidth: 286,
            searchFocusRequest: searchFocusRequest,
            onBack: viewModel.goBack,
            onSubmit: performPrimaryAction,
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false {
                    viewModel.goBack()
                }
            }
        ) {
            CommandlyOptionMenu(
                items: ProductivityLibraryFilter.allCases.map {
                    CommandlyOptionItem(id: $0.id, title: $0.title)
                },
                selectionID: viewModel.filter.id,
                allowsSearch: false,
                accessibilityLabelText: "Filter productivity library"
            ) { item in
                if let filter = ProductivityLibraryFilter(rawValue: item.id) {
                    viewModel.filter = filter
                }
            }
        } sidebar: {
            sidebar
        } detail: {
            detail
        }
        .task(id: viewModel.loadRequestID) {
            await viewModel.load()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingSnippet != nil },
            set: { if !$0 { viewModel.cancelSnippetInput() } }
        ), onDismiss: { searchFocusRequest += 1 }) {
            SnippetInputSheet(viewModel: viewModel)
        }
        .onChange(of: viewModel.editorMode != nil) { wasEditing, isEditing in
            if wasEditing && !isEditing { searchFocusRequest += 1 }
        }
        .onChange(of: viewModel.floatingNoteRevision) { _, _ in
            viewModel.refreshForFloatingNoteChanges()
        }
        .onChange(of: viewModel.canRefreshFromFloatingNotes) { _, ready in
            if ready { viewModel.refreshForFloatingNoteChanges() }
        }
        .alert("Delete this item?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("This removes the item from your local productivity library.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Productivity Library")
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeletionItem != nil },
            set: { isPresented in
                if isPresented == false { viewModel.cancelDelete() }
            }
        )
    }

    private func performPrimaryAction() {
        if viewModel.editorMode != nil {
            viewModel.perform(ProductivityLibraryActionID.saveDraft)
        } else if viewModel.selectedItem != nil {
            viewModel.perform(ProductivityLibraryActionID.useSelected)
        } else {
            viewModel.perform(ProductivityLibraryActionID.createItem)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.xs)) {
                Text("LIBRARY")
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.55)

                Spacer(minLength: 0)

                Menu {
                    if viewModel.canCreateFloatingNote {
                        Button("Floating Note", systemImage: "note.text", action: viewModel.createFloatingNote)
                        Divider()
                    }
                    ForEach(ProductivityLibraryItemKind.allCases) { kind in
                        Button {
                            viewModel.beginCreating(kind: kind)
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .commandlyFont(size: 11, weight: .semibold)
                        .frame(width: 26, height: 24)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(viewModel.loadState != .loaded || viewModel.isBusy)
                .help("Create a library item")
                .accessibilityLabel("Create library item")
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, density.spacing(.xs))

            Divider().opacity(0.3)

            if !viewModel.availableTags.isEmpty {
                Picker("Tag", selection: $viewModel.selectedTag) {
                    Text("All Tags").tag(nil as String?)
                    ForEach(viewModel.availableTags, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
                .padding(.horizontal, density.spacing(.sm))
                .padding(.vertical, density.spacing(.xs))
                .accessibilityIdentifier("productivity-library-tag-filter")
            }

            sidebarContent
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            VStack(spacing: density.spacing(.xs)) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading your library…")
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: density.spacing(.sm)) {
                LauncherApplicationEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Library unavailable",
                    message: "Your local library file couldn’t be read."
                )
                Button("Try Again") {
                    viewModel.requestReload()
                }
                .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                .padding(.bottom, density.spacing(.md))
            }
        case .loaded:
            if viewModel.filteredItems.isEmpty {
                VStack(spacing: density.spacing(.sm)) {
                    LauncherApplicationEmptyState(
                        systemImage: viewModel.items.isEmpty ? "books.vertical" : "magnifyingglass",
                        title: viewModel.items.isEmpty ? "Build your library" : "No matching items",
                        message: viewModel.items.isEmpty
                            ? "Save reusable text, notes, links, and emoji keywords."
                            : "Try a different search or filter."
                    )
                    if viewModel.items.isEmpty {
                        Button("Create First Item") {
                            viewModel.beginCreating()
                        }
                        .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                        .padding(.bottom, density.spacing(.md))
                    }
                }
            } else {
                itemList
            }
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: density.spacing(.xxs)) {
                    ForEach(viewModel.filteredItems) { item in
                        LauncherApplicationRow(
                            isSelected: viewModel.selectedItem?.id == item.id,
                            onSelect: { viewModel.select(item.id) },
                            onOpen: {
                                viewModel.select(item.id)
                                viewModel.perform(ProductivityLibraryActionID.useSelected)
                            },
                            onContextAction: { viewModel.presentActions(for: item.id) },
                            onHoverChange: { hovering in
                                if hovering { viewModel.select(item.id) }
                            }
                        ) {
                            ProductivityLibraryRowLabel(item: item)
                        } accessory: {
                            EmptyView()
                        }
                        .id(item.id)
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if viewModel.editorMode != nil {
            ProductivityLibraryEditor(viewModel: viewModel)
        } else if let item = viewModel.selectedItem {
            ProductivityLibraryItemDetail(viewModel: viewModel, item: item)
                .id(item.id)
        } else {
            LauncherApplicationEmptyState(
                systemImage: "square.grid.2x2",
                title: "Select an item",
                message: "Its contents and actions will appear here."
            )
        }
    }
}

private struct ProductivityLibraryRowLabel: View {
    let item: ProductivityLibraryItem

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.kind.systemImage)
                .symbolRenderingMode(.hierarchical)
                .commandlyFont(size: 13, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: 28, height: 28)
                .background(BrandPalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .commandlyFont(size: 11.5, weight: .semibold)
                    .lineLimit(1)
                Text(preview)
                    .commandlyFont(size: 9.5, weight: .regular)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.title), \(item.title)")
    }

    private var preview: String {
        item.content.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct ProductivityLibraryItemDetail: View {
    @Bindable var viewModel: ProductivityLibraryViewModel
    let item: ProductivityLibraryItem
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                HStack(alignment: .top, spacing: density.spacing(.sm)) {
                    Image(systemName: item.kind.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .commandlyFont(size: 21, weight: .semibold)
                        .foregroundStyle(BrandPalette.accentSoft)
                        .frame(width: 46, height: 46)
                        .background(
                            BrandPalette.accent.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 13)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .commandlyFont(size: 17, weight: .semibold)
                            .textSelection(.enabled)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.kind.title)
                            .commandlyFont(size: 9.5, weight: .semibold)
                            .foregroundStyle(BrandPalette.accentSoft)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(BrandPalette.accent.opacity(0.09), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                contentCard

                HStack(spacing: density.spacing(.xs)) {
                    Button(item.kind.primaryActionTitle) {
                        viewModel.perform(ProductivityLibraryActionID.useSelected)
                    }
                    .buttonStyle(ProductivityLibraryPrimaryButtonStyle())
                    .disabled(viewModel.isBusy)

                    Button("Edit") {
                        viewModel.beginEditingSelected()
                    }
                    .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                    .disabled(viewModel.isBusy)

                    ShareLink(item: item.content) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ProductivityLibrarySecondaryButtonStyle())

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        viewModel.requestDeleteSelected()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                    .disabled(viewModel.isBusy)
                    .help("Delete item")
                    .accessibilityLabel("Delete item")
                }

                if viewModel.canOpenFloatingNote {
                    Button("Open Floating Note", systemImage: "macwindow", action: viewModel.openSelectedFloatingNote)
                        .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                        .accessibilityIdentifier("library-open-floating-note")
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                    Text("DETAILS")
                        .commandlyFont(size: 9.5, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .tracking(0.55)
                    LauncherApplicationMetadataRow(label: "Type", value: item.kind.title)
                    if !item.tags.isEmpty {
                        LauncherApplicationMetadataRow(label: "Tags", value: item.tags.joined(separator: ", "))
                    }
                    LauncherApplicationMetadataRow(
                        label: "Updated",
                        value: item.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            .padding(density.spacing(.md))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind.title), \(item.title)")
    }

    @ViewBuilder
    private var contentCard: some View {
        VStack(alignment: .leading, spacing: density.spacing(.xs)) {
            Text(item.kind.contentLabel.uppercased())
                .commandlyFont(size: 9.5, weight: .semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.55)

            if item.kind == .emojiKeyword {
                Text(item.content)
                    .commandlyFont(size: 42)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                    .textSelection(.enabled)
            } else {
                Text(item.content)
                    .commandlyFont(
                        size: 12,
                        weight: .regular,
                        design: item.kind == .snippet ? .monospaced : .default
                    )
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    .textSelection(.enabled)
            }
        }
        .padding(density.spacing(.sm))
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
    }
}

private struct ProductivityLibraryEditor: View {
    @Bindable var viewModel: ProductivityLibraryViewModel
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editorTitle)
                        .commandlyFont(size: 17, weight: .semibold)
                    Text("Stored locally in Commandly’s Application Support folder.")
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                }

                Picker("Item type", selection: $viewModel.draft.kind) {
                    ForEach(ProductivityLibraryItemKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(viewModel.isSaving)
                .accessibilityLabel("Item type")

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("NAME")
                    TextField("A memorable name or emoji keyword", text: $viewModel.draft.title)
                        .focused($isTitleFocused)
                        .textFieldStyle(.plain)
                        .commandlyFont(size: 12, weight: .medium)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                        }
                        .disabled(viewModel.isSaving)
                        .accessibilityIdentifier("productivity-library-title")
                        .onAppear { isTitleFocused = true }
                }

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel(viewModel.draft.kind.contentLabel.uppercased())
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $viewModel.draft.content)
                            .commandlyFont(
                                size: 11.5,
                                design: viewModel.draft.kind == .snippet ? .monospaced : .default
                            )
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .disabled(viewModel.isSaving)
                            .accessibilityIdentifier("productivity-library-content")

                        if viewModel.draft.content.isEmpty {
                            Text(viewModel.draft.kind.contentPlaceholder)
                                .commandlyFont(size: 10.5)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 150)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("TAGS")
                    TextField("work, writing, personal", text: $viewModel.draft.tags)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Tags separated by commas")
                        .accessibilityIdentifier("productivity-library-tags")
                        .disabled(viewModel.isSaving)
                    Text("Separate with commas. Up to 12 tags, 32 characters each.")
                        .commandlyFont(size: 11)
                        .foregroundStyle(.secondary)
                }

                if viewModel.draft.kind == .snippet {
                    Label(
                        "Insert {{clipboard}}, {{date}}, {{time}}, {{datetime}}, or {{uuid}}. Use {{input:Name}} to ask for a value each time you copy.",
                        systemImage: "wand.and.stars"
                    )
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
                }

                if let validation = viewModel.draftValidationMessage {
                    Label(validation, systemImage: "exclamationmark.circle")
                        .commandlyFont(size: 10.5, weight: .medium)
                        .foregroundStyle(SemanticColors.color(for: .danger))
                }

                if viewModel.hasPersistenceConflict {
                    Button("Save as New Item", action: viewModel.saveDraftAsNew)
                        .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                        .disabled(viewModel.isBusy)
                        .accessibilityIdentifier("library-save-conflict-copy")
                }

                HStack(spacing: density.spacing(.xs)) {
                    Button(viewModel.isSaving ? "Saving…" : "Save") {
                        viewModel.saveDraft()
                    }
                    .buttonStyle(ProductivityLibraryPrimaryButtonStyle())
                    .disabled(viewModel.canSaveDraft == false)

                    Button("Cancel") {
                        viewModel.cancelEditor()
                    }
                    .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                    .disabled(viewModel.isSaving)

                    if viewModel.draft.content.isEmpty == false {
                        ShareLink(item: viewModel.draft.content) {
                            Label("Share Draft", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ProductivityLibrarySecondaryButtonStyle())
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(density.spacing(.md))
        }
    }

    private var editorTitle: String {
        switch viewModel.editorMode {
        case .creating: return "Create Library Item"
        case .editing: return "Edit Library Item"
        case nil: return "Library Item"
        }
    }

    private func editorLabel(_ value: String) -> some View {
        Text(value)
            .commandlyFont(size: 9.5, weight: .semibold)
            .foregroundStyle(.tertiary)
            .tracking(0.55)
    }
}

private struct ProductivityLibraryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .commandlyFont(size: 10.5, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 29)
            .background(
                BrandPalette.accent.opacity(configuration.isPressed ? 0.72 : 0.92),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}

private struct ProductivityLibrarySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .commandlyFont(size: 10.5, weight: .medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.09 : 0.05),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            }
    }
}

#Preview {
    ProductivityLibraryView(
        viewModel: ProductivityLibraryViewModel(
            services: .inMemory,
            onGoBack: {},
            onDismiss: {}
        )
    )
    .frame(width: LayoutConstants.launcherIdealWidth, height: LayoutConstants.launcherIdealHeight)
}
