import DesignSystem
import SwiftUI

struct QuickAIView: View {
    @Bindable var viewModel: QuickAIViewModel
    var title = "Quick AI"
    var subtitle = "A conversation, within reach"
    var contextDisclosure: String?
    var onRemember: ((QuickAIEntry) -> Void)?
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var isPromptFocused: Bool
    @State private var followsReply = true

    var body: some View {
        VStack(spacing: 0) {
            header.zIndex(2)
            if viewModel.selection != nil { modelDiscoveryBar }
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity).background(LauncherPalette.detail)
            Divider()
            composer
        }
        .onAppear { viewModel.start(); isPromptFocused = true }
        .onChange(of: viewModel.composerIsEnabled) { _, enabled in
            if enabled {
                // Catalog loading can finish after onAppear while the composer was disabled.
                DispatchQueue.main.async {
                    guard viewModel.composerIsEnabled else { return }
                    isPromptFocused = true
                }
            }
        }
        .onDisappear { viewModel.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title + " conversation")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)
            Image(systemName: "bubble.left.and.text.bubble.right")
                .commandlyFont(size: 16, weight: .medium).foregroundStyle(BrandPalette.accentSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).commandlyFont(size: 14, weight: .semibold)
                Text(subtitle).commandlyFont(size: 10).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if viewModel.selections.isEmpty == false {
                CommandlyOptionMenu(
                    items: viewModel.selections.map { .init(id: $0.id, title: $0.title) },
                    selectionID: viewModel.selection?.id ?? "",
                    placeholderTitle: "Choose a model",
                    searchPrompt: "Find a provider or model…",
                    accessibilityLabelText: "Chat provider and model"
                ) { viewModel.requestSelection($0.id) }
                .disabled(viewModel.isResponding || viewModel.isLoading || viewModel.isRefreshingModels)
                .help("Changing provider or model starts a new conversation.")
            }
            Button { viewModel.reset(); isPromptFocused = true } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless).accessibilityLabel("New chat")
        }
        .padding(.horizontal, density.spacing(.md)).padding(.vertical, density.spacing(.sm))
        .background(LauncherPalette.chrome)
    }

    private var modelDiscoveryBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(viewModel.modelRefreshDisclosure).commandlyFont(size: 10).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if viewModel.isRefreshingModels {
                    ProgressView().controlSize(.mini)
                    Button("Cancel", action: viewModel.cancelModelRefresh).buttonStyle(.borderless)
                        .accessibilityLabel("Cancel model refresh")
                } else {
                    Button("Refresh Models", action: viewModel.refreshModels).buttonStyle(.bordered)
                        .disabled(viewModel.canRefreshModels == false)
                        .accessibilityIdentifier("quick-ai-refresh-models")
                }
            }
            if let message = viewModel.modelRefreshMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: viewModel.modelRefreshFailed ? "exclamationmark.circle" : "info.circle")
                    Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .commandlyFont(size: 10).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quick-ai-model-status")
            }
        }
        .padding(.horizontal, density.spacing(.md)).padding(.bottom, density.spacing(.sm))
        .background(LauncherPalette.chrome)
    }

    @ViewBuilder private var content: some View {
        if let pending = viewModel.pendingSelection {
            VStack(spacing: density.spacing(.md)) {
                Image(systemName: "arrow.triangle.2.circlepath").commandlyFont(size: 26)
                Text("Start a new chat with \(pending.title)?").commandlyFont(size: 16, weight: .semibold)
                Text("The current conversation and draft will be cleared. Its messages will not be sent to the new provider.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Keep Current Chat", action: viewModel.cancelSelectionChange).buttonStyle(.bordered)
                    Button("Start New Chat") { viewModel.confirmSelectionChange(); isPromptFocused = true }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(density.spacing(.lg)).frame(maxWidth: 430)
        } else if viewModel.isLoading && viewModel.entries.isEmpty {
            ProgressView("Loading configured models…")
        } else if (viewModel.selection == nil || viewModel.loadError != nil) && viewModel.entries.isEmpty {
            VStack(spacing: density.spacing(.md)) {
                Image(systemName: "key.horizontal").commandlyFont(size: 28).foregroundStyle(.secondary)
                Text("Connect a provider to begin").commandlyFont(size: 18, weight: .semibold)
                Text(viewModel.loadError ?? "Choose your own AI provider and model in AI Settings. Opening this screen does not contact a provider.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Open AI Settings", action: viewModel.openSettings).buttonStyle(.borderedProminent)
                    Button("Check Again", action: viewModel.reloadChoices).buttonStyle(.bordered)
                }
            }.padding(density.spacing(.lg)).frame(maxWidth: 420)
        } else {
            conversation
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.lg)) {
                    if viewModel.entries.isEmpty {
                        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                            Text("What would you like to work through?").commandlyFont(size: 21, weight: .semibold)
                            Text("Ask a question, refine an idea, or draft a message. Follow up without repeating the context.")
                                .commandlyFont(size: 12).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                suggestion("Explain a concept", prompt: "Explain this concept in plain language: ")
                                suggestion("Improve a draft", prompt: "Help me improve this draft: ")
                            }.padding(.top, 5)
                        }.padding(.top, density.spacing(.lg))
                    }
                    ForEach(viewModel.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            QuickAIMessageView(entry: entry)
                            if let onRemember, [.complete, .limited].contains(entry.state), entry.text.isEmpty == false {
                                Button("Remember…") { onRemember(entry) }.buttonStyle(.borderless)
                                    .accessibilityLabel("Review this message as a saved memory")
                            }
                        }
                    }
                    if viewModel.canRetry {
                        Button("Retry Last Message", action: viewModel.retry).buttonStyle(.bordered)
                    }
                    if viewModel.needsReset {
                        Button("Start a New Chat", action: viewModel.reset).buttonStyle(.borderedProminent)
                    }
                    Color.clear.frame(height: 1).id("quick-ai-bottom")
                }.padding(density.spacing(.lg))
            }
            .onChange(of: viewModel.entries.last?.text) { _, _ in
                if followsReply { proxy.scrollTo("quick-ai-bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.entries.count) { _, _ in
                if followsReply { proxy.scrollTo("quick-ai-bottom", anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let contextDisclosure {
                Text(contextDisclosure).commandlyFont(size: 10).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(viewModel.disclosure).commandlyFont(size: 10).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write a message…", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain).commandlyFont(size: 12).lineLimit(1...5)
                    .focused($isPromptFocused)
                    .disabled(viewModel.composerIsEnabled == false)
                    .onSubmit { followsReply = true; viewModel.send() }
                    .onKeyPress(.escape) { viewModel.handleEscape() ? .handled : .ignored }
                    .accessibilityIdentifier("quick-ai-prompt").accessibilityLabel("Message to selected AI provider")
                Button {
                    if viewModel.isResponding { viewModel.stopReply() }
                    else { followsReply = true; viewModel.send() }
                } label: {
                    Image(systemName: viewModel.isResponding ? "stop.fill" : "arrow.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isResponding == false && viewModel.canSend == false)
                .accessibilityLabel(viewModel.isResponding ? "Stop reply" : "Send message")
            }
            .padding(density.spacing(.sm))
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Text(viewModel.composerHint).commandlyFont(size: 9).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Toggle("Follow reply", isOn: $followsReply).toggleStyle(.checkbox).commandlyFont(size: 9)
            }
        }
        .padding(.horizontal, density.spacing(.md)).padding(.vertical, density.spacing(.sm))
        .background(LauncherPalette.chrome)
    }

    private func suggestion(_ title: String, prompt: String) -> some View {
        Button(title) { viewModel.draft = prompt; isPromptFocused = true }
            .buttonStyle(.bordered).commandlyFont(size: 10)
    }
}

private struct QuickAIMessageView: View {
    let entry: QuickAIEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: entry.isUser ? "person.crop.circle" : "sparkle")
                Text(entry.isUser ? "You" : "Assistant").commandlyFont(size: 10, weight: .semibold)
                if let stateLabel { Text(stateLabel).commandlyFont(size: 9).foregroundStyle(.secondary) }
                if entry.state == .streaming { ProgressView().controlSize(.mini) }
            }.foregroundStyle(entry.isUser ? Color.secondary : BrandPalette.accentSoft)
            if entry.text.isEmpty == false {
                Text(entry.text).commandlyFont(size: 13).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if entry.state == .streaming {
                Text("Waiting for the first words…").commandlyFont(size: 12).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(entry.isUser ? 12 : 0)
        .background(entry.isUser ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
    private var stateLabel: String? {
        switch entry.state {
        case .complete: nil
        case .streaming: "Receiving"
        case .stopped: "Stopped · not sent as context"
        case .failed: "Incomplete · not sent as context"
        case .limited: "Response limit reached"
        case .refused: "Provider limited this response"
        }
    }
}
