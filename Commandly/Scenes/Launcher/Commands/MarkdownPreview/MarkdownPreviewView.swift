import CommandKit
import DesignSystem
import MarkdownPreviewKit
import SwiftUI
import UniformTypeIdentifiers

struct MarkdownPreviewView: View {
    @Bindable var viewModel: MarkdownPreviewViewModel
    let webController: MarkdownPreviewWebController

    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var isSearchFocused: Bool
    @State private var showsOutline: Bool
    @State private var searchResult = MarkdownPreviewSearchResult.empty
    @State private var actionQuery = ""
    @State private var navigationMessage: String?

    init(
        viewModel: MarkdownPreviewViewModel,
        webController: MarkdownPreviewWebController
    ) {
        self.viewModel = viewModel
        self.webController = webController
        _showsOutline = State(initialValue: viewModel.configuration.showsTableOfContents)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LauncherPalette.detail)

            statusBar
        }
        .fileImporter(
            isPresented: $viewModel.showsDocumentPicker,
            allowedContentTypes: Self.markdownContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .fileExporter(
            isPresented: $viewModel.showsHTMLExporter,
            document: htmlDocument,
            contentType: .html,
            defaultFilename: viewModel.suggestedHTMLFilename,
            onCompletion: viewModel.completeHTMLExport
        )
        .fileExporter(
            isPresented: $viewModel.showsPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: viewModel.suggestedPDFFilename,
            onCompletion: viewModel.completePDFExport
        )
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.openDroppedURLs(urls)
        }
        .overlay {
            if viewModel.showsActionsMenu {
                actionPanel
            }
        }
        .onAppear {
            webController.onSearchResult = { result in
                searchResult = result
            }
            webController.onNavigationFailure = { message in
                navigationMessage = message
            }
        }
        .onDisappear {
            webController.onSearchResult = nil
            webController.onNavigationFailure = nil
        }
        .onChange(of: viewModel.state) { _, state in
            switch state {
            case .empty, .loading, .loaded:
                navigationMessage = nil
            case .failure:
                break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown Preview")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            Image(systemName: "doc.richtext")
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: density.iconSize, height: density.iconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(documentTitle)
                    .commandlyFont(size: 13, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Local Markdown reader")
                    .commandlyFont(size: 8.5, weight: .medium)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 180, alignment: .leading)

            if viewModel.document != nil {
                searchField
                    .frame(maxWidth: 310)

                outlineButton
                sourceButton
                reloadButton
                zoomMenu
                actionsButton
            } else {
                Spacer(minLength: 0)

                Button("Choose File…", systemImage: "folder") {
                    viewModel.chooseDocument()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isLoading)
                .accessibilityHint("Opens a picker for a Markdown document")
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .background(LauncherPalette.surface)
        .overlay {
            keyboardCommands
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 10, weight: .semibold)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            TextField("Find in document", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .commandlyFont(size: 11, weight: .medium)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.findNext()
                }
                .accessibilityIdentifier("markdown-preview-search")

            if viewModel.searchQuery.isEmpty == false {
                Text(searchResultLabel)
                    .commandlyFont(size: 8.5, weight: .semibold, design: .monospaced)
                    .foregroundStyle(searchResult.errorMessage == nil ? Color.secondary : Color.red)
                    .accessibilityLabel(searchResultAccessibilityLabel)

                Button {
                    viewModel.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous match")

                Button {
                    viewModel.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next match")

                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear document search")
            }

            searchOptionsMenu
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
    }

    private var searchOptionsMenu: some View {
        Menu {
            Toggle("Match Case", isOn: searchOption(\.isCaseSensitive))
            Toggle("Whole Words", isOn: searchOption(\.matchesWholeWords))
            Toggle("Regular Expression", isOn: searchOption(\.usesRegularExpression))
        } label: {
            Image(systemName: "slider.horizontal.3")
                .commandlyFont(size: 9.5, weight: .semibold)
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Search options")
    }

    private var outlineButton: some View {
        Button {
            showsOutline.toggle()
        } label: {
            Image(systemName: showsOutline ? "sidebar.left" : "sidebar.left")
                .symbolVariant(showsOutline ? .fill : .none)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(controlBackground(isActive: showsOutline))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
        .disabled(viewModel.outline.isEmpty)
        .accessibilityLabel(showsOutline ? "Hide document outline" : "Show document outline")
        .accessibilityValue(viewModel.outline.isEmpty ? "No headings" : "\(viewModel.outline.count) headings")
        .help("Toggle Document Outline")
    }

    private var sourceButton: some View {
        Button {
            viewModel.toggleSource()
        } label: {
            Image(systemName: viewModel.showsSource ? "text.document.fill" : "text.document")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(controlBackground(isActive: viewModel.showsSource))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .accessibilityLabel(viewModel.showsSource ? "Show rendered preview" : "Show Markdown source")
        .help("Toggle Source (Shift-Command-M)")
    }

    private var reloadButton: some View {
        Button {
            viewModel.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(controlBackground(isActive: false))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.isLoading || viewModel.documentActionState != .idle)
        .accessibilityLabel("Reload Markdown document")
        .help("Reload (Command-R)")
    }

    private var zoomMenu: some View {
        Menu {
            Button("Zoom In") { viewModel.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { viewModel.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { viewModel.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        } label: {
            Text("\(Int((viewModel.zoom * 100).rounded()))%")
                .commandlyFont(size: 9.5, weight: .semibold, design: .monospaced)
                .frame(minWidth: 42, minHeight: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Document zoom")
        .accessibilityValue("\(Int((viewModel.zoom * 100).rounded())) percent")
    }

    private var actionsButton: some View {
        Button {
            viewModel.showsActionsMenu = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(controlBackground(isActive: viewModel.showsActionsMenu))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Markdown document actions")
        .help("Actions (Command-K)")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            emptyState
        case .loading(let filename):
            loadingState(filename: filename)
        case .failure(let filename, let failure):
            failureState(filename: filename, message: failure.message)
        case .loaded:
            documentReader
        }
    }

    private var emptyState: some View {
        VStack(spacing: density.spacing(.lg)) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .frame(width: 82, height: 82)
                Image(systemName: "doc.text.magnifyingglass")
                    .commandlyFont(size: 34, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            VStack(spacing: density.spacing(.xs)) {
                Text("Read Markdown without leaving Commandly")
                    .commandlyFont(size: 18, weight: .semibold)
                Text("Drop a Markdown file here, or choose one to render privately on this Mac.")
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            Button("Choose Markdown File…", systemImage: "folder") {
                viewModel.chooseDocument()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

            HStack(spacing: density.spacing(.md)) {
                Label("Local rendering", systemImage: "lock.fill")
                Label("Finder Quick Look", systemImage: "eye.fill")
                Label("HTML & PDF export", systemImage: "square.and.arrow.up")
            }
            .commandlyFont(size: 9.5, weight: .medium)
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(density.spacing(.lg))
    }

    private func loadingState(filename: String) -> some View {
        VStack(spacing: density.spacing(.sm)) {
            ProgressView()
                .controlSize(.small)
            Text("Rendering \(filename)…")
                .commandlyFont(size: 12, weight: .semibold)
                .lineLimit(1)
            Text("Reading and formatting locally")
                .commandlyFont(size: 9.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rendering \(filename) locally")
    }

    private func failureState(filename: String, message: String) -> some View {
        VStack(spacing: density.spacing(.lg)) {
            LauncherApplicationEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "Couldn’t preview \(filename)",
                message: message
            )
            .frame(maxHeight: 180)

            HStack(spacing: density.spacing(.sm)) {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    viewModel.reload()
                }
                .buttonStyle(.borderedProminent)

                Button("Choose Another File…", systemImage: "folder") {
                    viewModel.chooseDocument()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(density.spacing(.lg))
    }

    private var documentReader: some View {
        HStack(spacing: 0) {
            if showsOutline, viewModel.outline.isEmpty == false {
                outline
                    .frame(width: 220)
                    .background(LauncherPalette.sidebar)

                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(width: 1)
            }

            MarkdownPreviewWebView(controller: webController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(viewModel.showsSource ? "Markdown source" : "Rendered Markdown document")
        }
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OUTLINE")
                    .commandlyFont(size: 9, weight: .bold)
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(viewModel.outline.count)")
                    .commandlyFont(size: 8.5, weight: .semibold, design: .monospaced)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.top, density.spacing(.sm))
            .padding(.bottom, density.spacing(.xs))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.outline.enumerated()), id: \.offset) { _, entry in
                        outlineRow(entry)
                    }
                }
                .padding(.horizontal, density.spacing(.xs))
                .padding(.bottom, density.spacing(.sm))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document outline")
    }

    private func outlineRow(_ entry: MarkdownOutlineEntry) -> some View {
        let isSelected = entry.anchor == viewModel.selectedOutlineAnchor
        return Button {
            viewModel.selectOutlineEntry(entry)
        } label: {
            HStack(spacing: 7) {
                Text("H\(entry.level)")
                    .commandlyFont(size: 7.5, weight: .bold, design: .monospaced)
                    .foregroundStyle(
                        isSelected ? BrandPalette.accentSoft : Color.secondary.opacity(0.68)
                    )
                    .frame(width: 18)
                Text(entry.title)
                    .commandlyFont(size: 10.5, weight: isSelected ? .semibold : .medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(max(0, entry.level - 1)) * 7)
            .padding(.horizontal, density.spacing(.xs))
            .padding(.vertical, 6)
            .background(
                isSelected ? LauncherPalette.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .accessibilityValue("Heading level \(entry.level)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var statusBar: some View {
        if viewModel.document != nil || viewModel.statusMessage != nil || navigationMessage != nil {
            HStack(spacing: density.spacing(.sm)) {
                Label("On this Mac", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)

                if let message = searchResult.errorMessage ?? navigationMessage ?? viewModel.statusMessage {
                    Text(message)
                        .foregroundStyle(
                            searchResult.errorMessage == nil
                                ? Color.secondary.opacity(0.68)
                                : Color.red
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let document = viewModel.document {
                    if document.source.warnings.isEmpty == false {
                        Label(
                            "\(document.source.warnings.count) resource warnings",
                            systemImage: "exclamationmark.shield"
                        )
                        .foregroundStyle(.orange)
                        .accessibilityHint("Some local images were omitted by preview safety limits")
                    }

                    Text(document.source.encoding.rawValue)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)

                    Toggle("Auto reload", isOn: Binding(
                        get: { viewModel.autoReload },
                        set: viewModel.setAutoReload
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                }
            }
            .commandlyFont(size: 8.5, weight: .medium)
            .padding(.horizontal, density.spacing(.md))
            .frame(height: 27)
            .background(LauncherPalette.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(height: 1)
            }
        }
    }

    private var actionPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
                .onTapGesture {
                    viewModel.showsActionsMenu = false
                    actionQuery = ""
                }

            LauncherActionPanel(
                title: "Markdown Preview",
                actions: filteredActionItems,
                query: $actionQuery,
                onSelect: { actionID in
                    viewModel.showsActionsMenu = false
                    actionQuery = ""
                    viewModel.perform(actionID)
                },
                onDismiss: {
                    viewModel.showsActionsMenu = false
                    actionQuery = ""
                }
            )
            .padding(.trailing, density.spacing(.md))
            .padding(.bottom, density.spacing(.md))
        }
    }

    private var actionItems: [LauncherActionPanelItem] {
        viewModel.menuActions.map { action in
            LauncherActionPanelItem(
                id: action.id,
                title: action.title,
                systemImage: actionIcon(for: action.id),
                keyHint: action.keyHint,
                isDestructive: false,
                isEnabled: action.isEnabled,
                section: actionSection(for: action.id)
            )
        }
    }

    private var filteredActionItems: [LauncherActionPanelItem] {
        let query = actionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return actionItems }
        return actionItems.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var keyboardCommands: some View {
        Group {
            Button("Focus Find") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("Export HTML") { viewModel.requestHTMLExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export PDF") { viewModel.requestPDFExport() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Zoom In") { viewModel.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { viewModel.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { viewModel.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        }
        .labelsHidden()
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var documentTitle: String {
        switch viewModel.state {
        case .loading(let filename), .failure(let filename, _):
            filename
        case .loaded(let document):
            document.source.displayName
        case .empty:
            "Markdown Preview"
        }
    }

    private var searchResultLabel: String {
        if searchResult.errorMessage != nil { return "!" }
        return "\(searchResult.currentMatch)/\(searchResult.totalMatches)"
    }

    private var searchResultAccessibilityLabel: String {
        if let errorMessage = searchResult.errorMessage { return errorMessage }
        guard searchResult.totalMatches > 0 else { return "No matches" }
        return "Match \(searchResult.currentMatch) of \(searchResult.totalMatches)"
    }

    private var htmlDocument: MarkdownPreviewExportDocument? {
        viewModel.htmlExportData.map(MarkdownPreviewExportDocument.init(data:))
    }

    private var pdfDocument: MarkdownPreviewExportDocument? {
        viewModel.pdfExportData.map(MarkdownPreviewExportDocument.init(data:))
    }

    private func searchOption(
        _ keyPath: WritableKeyPath<MarkdownPreviewSearchOptions, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.searchOptions[keyPath: keyPath] },
            set: { value in
                var options = viewModel.searchOptions
                options[keyPath: keyPath] = value
                viewModel.searchOptions = options
            }
        )
    }

    private func controlBackground(isActive: Bool) -> Color {
        isActive ? LauncherPalette.selection : Color.primary.opacity(0.055)
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        viewModel.open(url)
    }

    private func actionIcon(for actionID: CommandActionID) -> String {
        switch actionID {
        case MarkdownPreviewActionID.chooseDocument: "folder"
        case MarkdownPreviewActionID.reload: "arrow.clockwise"
        case MarkdownPreviewActionID.toggleSource: "text.document"
        case MarkdownPreviewActionID.zoomIn: "plus.magnifyingglass"
        case MarkdownPreviewActionID.zoomOut: "minus.magnifyingglass"
        case MarkdownPreviewActionID.resetZoom: "1.magnifyingglass"
        case MarkdownPreviewActionID.toggleAutoReload: "arrow.triangle.2.circlepath"
        case MarkdownPreviewActionID.exportHTML: "chevron.left.forwardslash.chevron.right"
        case MarkdownPreviewActionID.exportPDF: "doc.richtext"
        case MarkdownPreviewActionID.printDocument: "printer"
        case MarkdownPreviewActionID.closeDocument: "xmark.circle"
        default: "ellipsis"
        }
    }

    private func actionSection(for actionID: CommandActionID) -> String {
        switch actionID {
        case MarkdownPreviewActionID.zoomIn,
             MarkdownPreviewActionID.zoomOut,
             MarkdownPreviewActionID.resetZoom:
            "view"
        case MarkdownPreviewActionID.exportHTML,
             MarkdownPreviewActionID.exportPDF,
             MarkdownPreviewActionID.printDocument:
            "export"
        default:
            "document"
        }
    }

    private static let markdownContentTypes: [UTType] = {
        let types = MarkdownPreviewFileTypes.fileExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        return types.isEmpty ? [.plainText] : Array(Set(types))
    }()
}

private struct MarkdownPreviewExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html, .pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
