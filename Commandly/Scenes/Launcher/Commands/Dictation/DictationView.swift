import DesignSystem
import Infrastructure
import SwiftUI

struct DictationView: View {
    @Bindable var viewModel: DictationViewModel
    @FocusState private var editorFocused: Bool
    @State private var showsStyles = false
    @State private var reviewScroll = ScrollPosition(edge: .top)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyBackButton(action: viewModel.goBack)
                Image(systemName: "waveform").accessibilityHidden(true)
                Text("Dictation").commandlyFont(size: 14, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer()
                Label("On-device speech", systemImage: "lock.shield").commandlyFont(size: 10).foregroundStyle(.secondary)
                Button("Saved Dictations", action: viewModel.presentHistory).controlSize(.small).disabled(viewModel.isBusy)
            }.padding(.horizontal, 14).padding(.vertical, 10).background(LauncherPalette.chrome)
            Divider().opacity(0.5)
            controls.padding(.horizontal, 14).padding(.vertical, 9)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    recordingStatus
                    if let fixture = viewModel.fixtureLabel { Label(fixture, systemImage: "testtube.2").commandlyFont(size: 10).foregroundStyle(.orange) }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").commandlyFont(size: 11).foregroundStyle(.orange)
                    }
                    if viewModel.reviewText.utf8.count > 64 * 1_024 {
                        Text("Shorten this draft to 64 KiB or fewer to copy or save it.").commandlyFont(size: 11).foregroundStyle(.orange)
                    }
                    TextEditor(text: $viewModel.reviewText).commandlyFont(size: 14).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 185).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                        .focused($editorFocused).disabled(viewModel.phase != .idle)
                        .accessibilityLabel(viewModel.phase == .recording ? "Live transcript" : "Review and edit dictation")
                    if viewModel.reviewText.isEmpty && viewModel.phase == .idle {
                        Text("Choose a language, then Start Dictation. Audio stays on this Mac; recording starts only after your explicit action.")
                            .commandlyFont(size: 11).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Writing Style · optional AI", isExpanded: $showsStyles) {
                        DictationStyleView(model: viewModel.styles, text: viewModel.reviewText, isRecording: viewModel.isBusy,
                            onUse: viewModel.useStylePreview, onSettings: viewModel.openAISettings)
                    }.commandlyFont(size: 12)
                    Text("Copy the reviewed text and paste it into your app. Audio is never saved; Save to History stores only the reviewed text.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(14)
            }
            .scrollPosition($reviewScroll)
            .onChange(of: viewModel.phase) { _, phase in
                if phase == .preparing || phase == .recording {
                    showsStyles = false
                    reviewScroll.scrollTo(edge: .top)
                }
            }
            Divider().opacity(0.5)
            HStack {
                Button("Copy Text", systemImage: "doc.on.doc", action: viewModel.copy)
                    .keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!viewModel.canCopy)
                Button("Save to History", action: viewModel.saveToHistory).disabled(!viewModel.canSave)
                Spacer(minLength: 6)
                if viewModel.phase == .recording {
                    Button("Cancel", action: viewModel.cancelRecording).help("Discard this recording and restore the previous draft")
                    Button("Stop & Review", action: viewModel.finishRecording).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                } else if viewModel.phase != .idle {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: viewModel.cancelRecording).disabled(viewModel.phase == .stopping)
                } else {
                    Button("Start Dictation", systemImage: "mic", action: viewModel.requestRecording)
                        .buttonStyle(.borderedProminent).disabled(!viewModel.canStart).keyboardShortcut(.return, modifiers: .command)
                }
            }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(LauncherPalette.detail)
        .task { viewModel.load() }
        .onChange(of: viewModel.focusRequest) { _, _ in editorFocused = true }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $viewModel.showsHistory, onDismiss: viewModel.closeHistory) {
            DictationHistoryView(model: viewModel.history, close: viewModel.closeHistory)
        }
        .alert("Start a new dictation?", isPresented: $viewModel.showsReplaceConfirmation) {
            Button("Keep Draft", role: .cancel) {}
            Button("Start New", action: viewModel.beginRecording)
        } message: { Text("The new transcript will replace this draft. Cancel Recording restores it; save or copy the draft first if you want to keep it.") }
        .alert("Leave this unsaved draft?", isPresented: $viewModel.showsLeaveConfirmation) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft", role: .destructive, action: viewModel.leaveDiscardingDraft)
        } message: { Text("This text has not been saved to History. Leaving removes this session’s draft.") }
        .accessibilityElement(children: .contain).accessibilityLabel("Dictation")
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Language", selection: $viewModel.languageID) {
                    if viewModel.languages.isEmpty { Text("Loading languages…").tag("") }
                    ForEach(viewModel.languages) { Text($0.name).tag($0.id) }
                }.disabled(viewModel.isBusy || viewModel.isLoading)
                Picker("Microphone", selection: $viewModel.microphoneID) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.microphones) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(viewModel.isBusy || viewModel.isLoading)
                Button { viewModel.refreshMicrophones() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel("Refresh microphones").disabled(viewModel.isBusy || viewModel.isLoading)
            }.controlSize(.small)
            HStack {
                Text(languageHint).commandlyFont(size: 10).foregroundStyle(.secondary)
                Spacer()
                if viewModel.isDownloading {
                    ProgressView().controlSize(.small)
                    Button("Cancel Download", action: viewModel.cancelDownload).controlSize(.small)
                } else if viewModel.availability == .downloadRequired {
                    Button("Download Language", action: viewModel.downloadLanguage).controlSize(.small).disabled(viewModel.isBusy)
                } else {
                    Button("Refresh Language", action: viewModel.checkAvailability).controlSize(.small).disabled(viewModel.isBusy)
                }
                Button("Microphone Settings…", action: viewModel.openMicrophoneSettings).controlSize(.small)
            }
        }
    }
    private var languageHint: String {
        if viewModel.isCheckingAvailability || viewModel.isLoading { return "Checking on-device support…" }
        if viewModel.isDownloading { return "Apple manages the model download; shared assets may remain after cancellation." }
        switch viewModel.availability {
        case .installed: return "Chosen language only · no spoken-language autodetection"
        case .downloadRequired: return "Model required. Downloading may release an older unused Commandly language reservation."
        case .downloading: return "A model download is in progress. Refresh Language after it finishes."
        case .unsupported: return "Choose a supported on-device language."
        }
    }
    @ViewBuilder private var recordingStatus: some View {
        HStack {
            if viewModel.phase == .recording, let startedAt = viewModel.startedAt {
                Circle().fill(.red).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("Recording · " + (viewModel.microphoneName ?? "Microphone")).commandlyFont(size: 12, weight: .semibold)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let seconds = max(0, Int(timeline.date.timeIntervalSince(startedAt)))
                    Text(String(format: "%02d:%02d / 05:00", seconds / 60, seconds % 60)).monospacedDigit().commandlyFont(size: 12)
                        .accessibilityLabel("Recording duration \(seconds) seconds. Five-minute limit.")
                }
            } else {
                Text(viewModel.phase == .preparing ? "Preparing microphone…" : viewModel.phase == .stopping ? "Stopping microphone and finishing text…" : "Review")
                    .commandlyFont(size: 12, weight: .semibold)
                Spacer()
                if viewModel.hasProvisionalText { Text("Includes provisional text").commandlyFont(size: 10).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct DictationStyleView: View {
    @Bindable var model: DictationStyleViewModel
    let text: String
    let isRecording: Bool
    let onUse: () -> Void
    let onSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Picker("Style", selection: $model.style) { ForEach(DictationWritingStyle.allCases) { Text($0.rawValue).tag($0) } }
                if !model.choices.isEmpty {
                    Picker("Model", selection: $model.providerID) { ForEach(model.choices) { Text($0.title).tag($0.id) } }
                }
                Button("AI Settings…", action: onSettings)
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh saved AI connections")
            }.controlSize(.small).disabled(isRecording || model.isLoading)
            Text(model.provider.map { "Preview Style sends only this reviewed text to \($0.title). Audio stays on your Mac. Original text remains unchanged until you use the suggestion." }
                 ?? "Connect a provider to preview a writing style. This optional action sends reviewed text, never microphone audio.")
                .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.isWorking {
                HStack { ProgressView().controlSize(.small); Text("Preparing style preview…"); Button("Cancel", action: model.invalidate) }
            } else {
                Button("Preview Style") { model.rewrite(text) }.disabled(isRecording || !model.canRewrite(text))
            }
            if let error = model.errorMessage { Text(error).commandlyFont(size: 11).foregroundStyle(.orange) }
            if model.originalText != nil {
                Text("Suggested version").commandlyFont(size: 11, weight: .medium)
                TextEditor(text: $model.proposedText).commandlyFont(size: 13).frame(height: 110).accessibilityLabel("Edit suggested writing style")
                HStack {
                    Button("Keep Original", action: model.invalidate)
                    Button("Use This Version", action: onUse).disabled(isRecording || model.result(for: text) == nil)
                }.controlSize(.small)
            }
            if text.utf8.count > 8 * 1_024 { Text("Shorten the draft to 8 KiB or fewer for an AI style preview.").commandlyFont(size: 10).foregroundStyle(.secondary) }
        }.padding(.top, 8)
    }
}
