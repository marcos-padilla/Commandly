import DesignSystem
import Infrastructure
import SwiftUI

struct GIFSearchView: View {
    @Bindable var viewModel: GIFSearchViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyBackButton(action: viewModel.goBack)
                Text("GIF Search").commandlyFont(size: 14, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer()
                attribution
                Button("Connection…", action: viewModel.openConnection).controlSize(.small)
            }.padding(.horizontal, 14).padding(.vertical, 10).background(LauncherPalette.chrome)
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                TextField("Search reactions and animated GIFs", text: $viewModel.query)
                    .textFieldStyle(.plain).commandlyFont(size: 14).focused($searchFocused)
                    .accessibilityLabel("Search GIPHY").onSubmit(viewModel.submitFromKeyboard)
                    .onKeyPress(.downArrow) { guard !viewModel.items.isEmpty else { return .ignored }; viewModel.moveSelection(offset: 1); return .handled }
                    .onKeyPress(.upArrow) { guard !viewModel.items.isEmpty else { return .ignored }; viewModel.moveSelection(offset: -1); return .handled }
                Picker("Maximum rating", selection: $viewModel.rating) {
                    ForEach(GIFContentRating.allCases) { Text($0.rawValue.uppercased()).tag($0) }
                }.labelsHidden().accessibilityLabel("Maximum GIF content rating").frame(width: 76)
                Button("Search", action: viewModel.submitSearch).disabled(!viewModel.canSearch)
                Button("Trending", action: viewModel.loadTrending).disabled(!viewModel.canSearch)
            }.controlSize(.small).padding(14)
            Divider().opacity(0.5)
            if viewModel.connection?.isConfigured != true {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connect your GIF catalog", systemImage: "rectangle.on.rectangle").commandlyFont(size: 17, weight: .semibold)
                    Text("Add your own GIPHY API key to search reactions, preview animations, and copy or save an original GIF.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary)
                    Button("Set Up GIPHY…", action: viewModel.openConnection).buttonStyle(.borderedProminent)
                    Text("Your search terms and media requests go directly to GIPHY. Opening this tool makes no catalog request.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                results
            }
            if viewModel.fixtureLabel != nil || viewModel.errorMessage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let fixture = viewModel.fixtureLabel { Label(fixture, systemImage: "testtube.2").foregroundStyle(.orange) }
                    if let error = viewModel.errorMessage { Text(error).foregroundStyle(.orange) }
                }.commandlyFont(size: 11).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 5)
            }
            Divider().opacity(0.5)
            HStack {
                Button("Previous", action: viewModel.previousPage).disabled(!viewModel.canGoPrevious)
                if !viewModel.items.isEmpty {
                    Text("\(viewModel.currentOffset + 1)–\(viewModel.currentOffset + viewModel.items.count)").commandlyFont(size: 10).foregroundStyle(.secondary)
                }
                Button("Next", action: viewModel.nextPage).disabled(!viewModel.canGoNext)
                Spacer()
                if viewModel.isExporting { ProgressView().controlSize(.small) }
                Button("Save GIF…") { viewModel.export(.save) }.disabled(!viewModel.canExport)
                Button("Copy Animated GIF") { viewModel.export(.copy) }.disabled(!viewModel.canExport).keyboardShortcut("c", modifiers: [.command, .shift])
            }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(LauncherPalette.detail)
        .onAppear { viewModel.setReduceMotion(reduceMotion) }
        .task { viewModel.load() }
        .onChange(of: reduceMotion) { _, value in viewModel.setReduceMotion(value) }
        .onChange(of: viewModel.focusRequest) { _, _ in searchFocused = true }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $viewModel.showsConnection, onDismiss: viewModel.closeConnection) { GIFConnectionView(model: viewModel) }
        .accessibilityElement(children: .contain).accessibilityLabel("Animated GIF search")
    }
    private var attribution: some View {
        Image("GIPHYAttribution").resizable().scaledToFit().frame(width: 200, height: 28)
            .accessibilityLabel("Powered by GIPHY")
    }
    private var results: some View {
        HStack(spacing: 0) {
            if viewModel.isSearching {
                VStack(spacing: 10) { ProgressView().controlSize(.small); Text("Searching GIPHY…").commandlyFont(size: 12).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                Text("Search a phrase or load Trending. Nothing is sent while you type.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $viewModel.selectedID) {
                        ForEach(viewModel.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).commandlyFont(size: 12, weight: .medium).lineLimit(2)
                                if let creator = item.creator ?? item.sourceName { Text(creator).commandlyFont(size: 10).foregroundStyle(.secondary).lineLimit(1) }
                            }.padding(.vertical, 5).tag(item.id).id(item.id)
                                .accessibilityElement(children: .combine).accessibilityLabel(GIFSearchViewModel.resultAccessibilityLabel(for: item))
                        }
                    }.listStyle(.sidebar).frame(width: 260).accessibilityLabel("GIPHY results in provider order")
                        .onKeyPress(.return) { viewModel.export(.copy); return .handled }
                        .onChange(of: viewModel.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
                Divider().opacity(0.5)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minHeight: 0, maxHeight: .infinity)
    }
    @ViewBuilder private var preview: some View {
        if let item = viewModel.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let animation = viewModel.animation {
                        GIFAnimationView(animation: animation, isPlaying: viewModel.isPlaying)
                            .frame(maxWidth: .infinity).frame(height: 200).accessibilityElement(children: .ignore).accessibilityLabel(item.accessibilityText)
                        HStack {
                            Button(reduceMotion ? "Still Preview" : viewModel.isPlaying ? "Pause Preview" : "Play Preview", action: viewModel.togglePreviewPlayback)
                                .controlSize(.small).disabled(!viewModel.canTogglePreviewPlayback)
                            Spacer(); Text("\(animation.originalFrameCount) frames").commandlyFont(size: 10).foregroundStyle(.secondary)
                        }
                    } else if viewModel.isLoadingPreview {
                        ProgressView("Loading animated preview…").controlSize(.small).frame(maxWidth: .infinity).frame(height: 200)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(viewModel.previewError ?? "Select a GIF to preview it.").commandlyFont(size: 11).foregroundStyle(.secondary)
                            Button("Retry Preview", action: viewModel.loadPreview).controlSize(.small)
                        }.frame(maxWidth: .infinity).frame(height: 200)
                    }
                    Text(item.title).commandlyFont(size: 13, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    if let creator = item.creator { Text("By " + creator).commandlyFont(size: 11).foregroundStyle(.secondary) }
                    HStack {
                        Button("View on GIPHY", action: viewModel.openGIPHYPage).disabled(item.pageURL == nil)
                        if let source = item.sourceName { Button("Source: " + source, action: viewModel.openCreatorSource).disabled(item.sourceURL == nil) }
                    }.controlSize(.small)
                    Text("Copy and Save fetch the original animation. Some destination apps only paste still images; save the .gif file when needed.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(14)
            }.id(item.id).accessibilityElement(children: .contain).accessibilityLabel("Selected GIF preview and attribution")
        }
    }
}

private struct GIFAnimationView: View {
    let animation: GIFDecodedAnimation
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()
    @State private var frozenElapsed = 0.0
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 0 : isPlaying ? timeline.date.timeIntervalSince(origin) : frozenElapsed
            if let frame = animation.frame(at: elapsed) {
                Image(decorative: frame, scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onChange(of: animation.id) { _, _ in origin = Date(); frozenElapsed = 0 }
        .onChange(of: isPlaying) { _, playing in
            if playing { origin = Date().addingTimeInterval(-frozenElapsed) }
            else { frozenElapsed = max(0, Date().timeIntervalSince(origin)) }
        }
        .overlay(alignment: .bottomLeading) {
            if reduceMotion { Text("Reduce Motion · still preview").commandlyFont(size: 10).padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)) }
        }
        .id(animation.id)
    }
}
