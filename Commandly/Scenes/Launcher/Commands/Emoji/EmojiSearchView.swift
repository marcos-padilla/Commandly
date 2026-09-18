import DesignSystem
import SwiftUI

struct EmojiSearchView: View {
    @Bindable var viewModel: EmojiSearchViewModel
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var focus: Focus?
    private enum Focus { case query, grid }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: viewModel.mode == .local ? "magnifyingglass" : "sparkles").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField(viewModel.mode == .local ? "Search names, keywords, or paste an emoji" : "Describe a feeling, idea, or occasion", text: $viewModel.query)
                        .textFieldStyle(.plain).commandlyFont(size: 14).focused($focus, equals: .query)
                        .accessibilityLabel(viewModel.mode == .local ? "Search the emoji catalog" : "Description for AI emoji search")
                        .onSubmit(viewModel.submit)
                        .onKeyPress(.downArrow) { viewModel.moveSelection(offset: 1); return .handled }
                        .onKeyPress(.upArrow) { viewModel.moveSelection(offset: -1); return .handled }
                    if viewModel.isSearching || viewModel.isFindingWithAI || viewModel.isLoading { ProgressView().controlSize(.small) }
                    if !viewModel.query.isEmpty {
                        Button { viewModel.query = ""; focus = .query } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear emoji search")
                    }
                }
                if viewModel.mode == .local { localOptions } else { aiOptions }
            }
            .padding(.horizontal, density.spacing(.md)).padding(.vertical, 10)
            Divider().opacity(0.5)
            if let error = viewModel.errorMessage { message(error, symbol: "exclamationmark.triangle") }
            HStack(spacing: 0) {
                results.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.5)
                detail.frame(width: 210).frame(maxHeight: .infinity)
            }
        }
        .background(LauncherPalette.detail)
        .task { viewModel.start() }
        .onAppear { DispatchQueue.main.async { focus = .query } }
        .onChange(of: viewModel.focusRequest) { _, _ in focus = .query }
        .onChange(of: viewModel.mode) { _, _ in focus = .query }
        .onDisappear { viewModel.stop() }
        .accessibilityElement(children: .contain).accessibilityLabel("Emoji Search")
    }

    private var header: some View {
        HStack(spacing: 10) {
            CommandlyBackButton(action: viewModel.goBack)
            Text("Emoji Search").commandlyFont(size: 14, weight: .semibold).accessibilityAddTraits(.isHeader)
            Spacer()
            Picker("Search method", selection: $viewModel.mode) {
                ForEach(EmojiSearchMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Search method").frame(width: 185)
        }
        .padding(.horizontal, density.spacing(.md)).padding(.vertical, 9).background(LauncherPalette.chrome)
    }

    private var localOptions: some View {
        HStack {
            Picker("Category", selection: $viewModel.category) {
                Text("All Categories").tag(String?.none)
                ForEach(viewModel.categories, id: \.self) { Text($0).tag(Optional($0)) }
            }.labelsHidden().accessibilityLabel("Emoji category").frame(maxWidth: 240)
            Toggle("Show all skin tones", isOn: $viewModel.includesVariants).toggleStyle(.checkbox).commandlyFont(size: 11)
            Spacer(minLength: 0)
            Text("Local").commandlyFont(size: 10).foregroundStyle(.secondary)
        }
    }

    private var aiOptions: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if viewModel.choices.isEmpty {
                    Text(viewModel.isLoadingChoices ? "Loading saved connections…" : "Connect a provider in AI Settings")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                } else {
                    Picker("AI provider and model", selection: $viewModel.providerID) {
                        ForEach(viewModel.choices) { Text($0.title).tag($0.id) }
                    }.labelsHidden().accessibilityLabel("AI provider and model")
                }
                Spacer(minLength: 4)
                Button("AI Settings…") { viewModel.perform(EmojiSearchActionID.settings) }.controlSize(.small)
                if viewModel.isFindingWithAI {
                    Button("Cancel") { viewModel.perform(EmojiSearchActionID.cancel) }.controlSize(.small)
                } else {
                    Button("Find with AI", action: viewModel.findWithAI).controlSize(.small).disabled(!viewModel.canFindWithAI)
                }
            }
            Text(viewModel.providerError ?? disclosure).commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclosure: String {
        guard let provider = viewModel.provider else { return "Optional AI search sends only your description after you choose Find with AI. Your saved emoji keywords stay local." }
        if !provider.supportsStreaming { return "This saved provider does not support the text runtime. Choose another provider in AI Settings." }
        return "Find with AI sends only this description to \(provider.title). Suggestions are checked against the Unicode catalog."
    }

    @ViewBuilder private var results: some View {
        let gridSelectionID = viewModel.gridSelectionID
        if viewModel.entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: viewModel.mode == .ai ? "sparkles" : "face.smiling").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(emptyTitle).commandlyFont(size: 14, weight: .medium)
                Text(emptyMessage).commandlyFont(size: 11).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                        ForEach(viewModel.entries) { entry in
                            Button { viewModel.select(entry); focus = .grid } label: {
                                VStack(spacing: 3) {
                                    Text(entry.symbol).font(.system(size: 29)).accessibilityHidden(true)
                                    Text(entry.name).commandlyFont(size: 9).lineLimit(2).multilineTextAlignment(.center).frame(height: 26)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(entry.id == gridSelectionID ? LauncherPalette.selection : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(entry.id == gridSelectionID ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).focusable(false)
                            .accessibilityLabel(entry.name).accessibilityValue(entry.id == gridSelectionID ? "Selected" : "")
                            .accessibilityHint("Selects for preview. Use Copy Emoji to copy.").id(entry.id)
                        }
                    }.padding(8)
                }
                .focusable().focused($focus, equals: .grid)
                .accessibilityLabel("Emoji results, six columns")
                .onKeyPress(.leftArrow) { viewModel.moveCell(offset: -1); return .handled }
                .onKeyPress(.rightArrow) { viewModel.moveCell(offset: 1); return .handled }
                .onKeyPress(.upArrow) { viewModel.moveSelection(offset: -1); return .handled }
                .onKeyPress(.downArrow) { viewModel.moveSelection(offset: 1); return .handled }
                .onKeyPress(.return) { viewModel.submit(); return .handled }
                .onChange(of: viewModel.selectedID) { _, _ in
                    if let id = viewModel.gridSelectionID { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let entry = viewModel.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.symbol).font(.system(size: 58)).frame(maxWidth: .infinity).padding(.top, 8).accessibilityHidden(true)
                    Text(entry.name).commandlyFont(size: 14, weight: .semibold).textSelection(.enabled)
                    Text(entry.category + " · " + entry.subgroup.replacingOccurrences(of: "-", with: " "))
                        .commandlyFont(size: 10).foregroundStyle(.secondary)
                    if viewModel.variants.count > 1 {
                        Picker("Variant", selection: Binding(get: { entry.symbol }, set: viewModel.selectVariant)) {
                            ForEach(viewModel.variants) { Text($0.symbol + " " + $0.name).tag($0.symbol) }
                        }.pickerStyle(.menu).accessibilityLabel("Skin tone variant")
                    }
                    Button("Copy Emoji", systemImage: "doc.on.doc", action: viewModel.copy)
                        .buttonStyle(.borderedProminent).disabled(!viewModel.canCopy)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    if !entry.keywords.isEmpty {
                        Text(entry.keywords.joined(separator: " · ")).commandlyFont(size: 10).foregroundStyle(.secondary)
                    }
                    Text(entry.codePoints).commandlyFont(size: 9, design: .monospaced).foregroundStyle(.tertiary).textSelection(.enabled)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(entry.id).accessibilityElement(children: .contain).accessibilityLabel("Selected emoji preview")
        } else {
            Text("Choose an emoji to see its name and variants.").commandlyFont(size: 11).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(20)
        }
    }

    private var emptyTitle: String {
        if viewModel.isLoading { return "Loading catalog…" }
        if viewModel.isSearching { return "Searching…" }
        if viewModel.isFindingWithAI { return "Finding emoji with AI…" }
        return viewModel.mode == .ai && !viewModel.hasAIResult ? "Describe the idea" : "No matching emoji"
    }
    private var emptyMessage: String {
        viewModel.mode == .ai ? "Try “quiet pride after finishing a difficult project.” Choose Find with AI when ready." : "Try an English name, category, keyword, or skin tone. Pasting an emoji finds its exact sequence."
    }
    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).commandlyFont(size: 11).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 6)
    }
}
