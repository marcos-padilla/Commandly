import DesignSystem
import Infrastructure
import SwiftUI

struct SlackEmojiView: View {
    @Bindable var model: SlackEmojiViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyBackButton(action: model.goBack)
                Text("Slack Emoji").commandlyFont(size: 14, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer()
                if !model.workspaces.isEmpty {
                    Picker("Workspace", selection: $model.workspaceID) {
                        ForEach(model.workspaces) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().accessibilityLabel("Slack workspace").frame(maxWidth: 240)
                        .disabled(model.isChangingConnection)
                }
                Button("Workspaces…", action: model.openConnections)
            }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10).background(LauncherPalette.chrome)
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                TextField("Search custom emoji names and aliases", text: $model.query)
                    .textFieldStyle(.plain).commandlyFont(size: 14).focused($searchFocused).accessibilityLabel("Search workspace emoji locally")
                    .onSubmit(model.submit)
                    .onKeyPress(.downArrow) { guard !model.items.isEmpty else { return .ignored }; model.moveSelection(offset: 1); return .handled }
                    .onKeyPress(.upArrow) { guard !model.items.isEmpty else { return .ignored }; model.moveSelection(offset: -1); return .handled }
                if model.isRefreshing || model.isFiltering { ProgressView().controlSize(.small) }
                Button("Refresh Emoji", action: model.refresh).controlSize(.small).disabled(!model.canRefresh)
            }.padding(14)
            Divider().opacity(0.5)
            content.frame(minHeight: 0, maxHeight: .infinity)
            if model.fixtureLabel != nil || model.errorMessage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let fixture = model.fixtureLabel { Label(fixture, systemImage: "testtube.2").foregroundStyle(.orange) }
                    if let error = model.errorMessage { Text(error).foregroundStyle(.orange) }
                }.commandlyFont(size: 11).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 5)
            }
            Divider().opacity(0.5)
            HStack {
                if let catalog = model.catalog {
                    Text(model.totalMatches > model.items.count ? "Showing \(model.items.count) of \(model.totalMatches) matches — refine the search" : "\(model.totalMatches) \(model.totalMatches == 1 ? "match" : "matches") · \(catalog.count) workspace names")
                        .commandlyFont(size: 10).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isExporting { ProgressView().controlSize(.small) }
                Button("Save Image…") { model.exportImage(save: true) }.disabled(!model.canExportImage)
                Button("Copy Image") { model.exportImage(save: false) }.disabled(!model.canExportImage).keyboardShortcut("c", modifiers: [.command, .shift])
            }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10)
        }.background(LauncherPalette.detail)
            .onAppear { model.setReduceMotion(reduceMotion) }.task { model.load() }
            .onChange(of: reduceMotion) { _, value in model.setReduceMotion(value) }
            .onChange(of: model.focusRequest) { _, _ in searchFocused = true }
            .onDisappear { model.stop() }
            .sheet(isPresented: $model.showsConnections, onDismiss: model.closeConnections) { SlackEmojiConnectionView(model: model) }
            .accessibilityElement(children: .contain).accessibilityLabel("Slack workspace custom emoji")
    }
    @ViewBuilder private var content: some View {
        if model.isLoading || model.isRefreshing {
            VStack(spacing: 10) { ProgressView().controlSize(.small); Text(model.isLoading ? "Loading saved workspace connections…" : "Refreshing this workspace's custom emoji…").commandlyFont(size: 12).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.workspace == nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your workspace, your emoji", systemImage: "face.smiling").commandlyFont(size: 17, weight: .semibold)
                    Text("Connect your own internal Slack app with only emoji:read. Refresh its custom emoji, then search names locally and copy a Slack name or original image.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Set Up Workspace…", action: model.openConnections).buttonStyle(.borderedProminent)
                    Text("Opening this tool makes no Slack request. No messages are read or sent.").commandlyFont(size: 11).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if model.catalog == nil {
            Text("Choose Refresh Emoji to load this workspace's custom names. Searching afterward stays on this Mac.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            Text(model.isFiltering ? "Searching names…" : "No matching custom emoji. Try a shorter name or refresh workspace changes.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedName) {
                        ForEach(model.items) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.shortcode).commandlyFont(size: 12, weight: .medium).lineLimit(1)
                                Text(SlackEmojiViewModel.resolutionDescription(item)).commandlyFont(size: 10).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.vertical, 4).tag(item.name).id(item.name)
                                .accessibilityElement(children: .combine).accessibilityLabel(item.shortcode + ". " + SlackEmojiViewModel.resolutionDescription(item))
                        }
                    }.listStyle(.sidebar).frame(width: 260).accessibilityLabel("Workspace emoji names and aliases")
                        .onKeyPress(.return) { model.copyName(); return .handled }
                        .onChange(of: model.selectedName) { _, value in if let value { proxy.scrollTo(value) } }
                }
                Divider().opacity(0.5)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    @ViewBuilder private var detail: some View {
        if let selected = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let preview = model.preview {
                        SlackEmojiPreviewView(preview: preview, isPlaying: model.isPlaying).frame(maxWidth: .infinity).frame(height: 150)
                            .accessibilityElement(children: .ignore).accessibilityLabel("Image for " + selected.shortcode)
                        if preview.animation != nil {
                            Button(reduceMotion ? "Still Preview" : model.isPlaying ? "Pause Preview" : "Play Preview", action: model.togglePlayback)
                                .controlSize(.small).disabled(!model.canTogglePlayback)
                        }
                    } else if model.isLoadingPreview {
                        ProgressView("Loading emoji preview…").controlSize(.small).frame(maxWidth: .infinity).frame(height: 150)
                    } else {
                        Image(systemName: "face.smiling").font(.system(size: 36)).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 90).accessibilityHidden(true)
                        if let error = model.previewError { Text(error).commandlyFont(size: 11).foregroundStyle(.secondary); Button("Retry Preview", action: model.loadPreview).controlSize(.small) }
                    }
                    Text(selected.shortcode).commandlyFont(size: 14, weight: .semibold).textSelection(.enabled)
                    Text(SlackEmojiViewModel.resolutionDescription(selected)).commandlyFont(size: 11).foregroundStyle(.secondary)
                    if let workspace = model.workspace { Text("From " + workspace.name).commandlyFont(size: 11).foregroundStyle(.secondary) }
                    Text("Return copies the Slack name. Copy Image and Save preserve the original image, including GIF animation. Use workspace content only where you have permission.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(14)
            }.id(selected.name).accessibilityElement(children: .contain).accessibilityLabel("Selected workspace emoji")
        }
    }
}
private struct SlackEmojiPreviewView: View {
    let preview: SlackEmojiPreview
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()
    @State private var pausedElapsed = 0.0
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: preview.animation == nil || !isPlaying || reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 0 : isPlaying ? timeline.date.timeIntervalSince(origin) : pausedElapsed
            let image = preview.animation?.frame(at: elapsed) ?? preview.image
            Image(decorative: image, scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onChange(of: isPlaying) { _, value in
            if value { origin = Date().addingTimeInterval(-pausedElapsed) } else { pausedElapsed = max(0, Date().timeIntervalSince(origin)) }
        }
        .overlay(alignment: .bottomLeading) { if reduceMotion, preview.animation != nil { Text("Reduce Motion · still preview").commandlyFont(size: 10).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4)) } }
        .id(preview.id)
    }
}
