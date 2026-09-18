import DesignSystem
import Infrastructure
import SwiftUI

struct TranslationView: View {
    @Bindable var viewModel: TranslationViewModel
    let nativeBridge: NativeTranslationBridge?
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.sm)) {
                CommandlyBackButton(action: viewModel.goBack)
                Image(systemName: "character.bubble").accessibilityHidden(true)
                Text(viewModel.isWordMode ? "Word Translation" : "Translate")
                    .commandlyFont(size: 15, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer()
                Label("On-device", systemImage: "lock.shield").commandlyFont(size: 10).foregroundStyle(.secondary)
            }
            .padding(density.spacing(.md))
            Rectangle().fill(LauncherPalette.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                    languages
                    if viewModel.isWordMode {
                        TextField("Enter a word or short phrase", text: $viewModel.input)
                            .textFieldStyle(.roundedBorder).focused($inputFocused)
                            .accessibilityLabel("Word to translate")
                            .onSubmit { viewModel.translate() }
                        output.frame(minHeight: 150, maxHeight: 190)
                    } else {
                        HStack(alignment: .top, spacing: density.spacing(.sm)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Original text").commandlyFont(size: 11, weight: .medium)
                                TextEditor(text: $viewModel.input).font(.body).scrollContentBackground(.hidden)
                                    .focused($inputFocused).accessibilityLabel("Text to translate")
                                Text("\(viewModel.input.count) / 10,000 characters")
                                    .commandlyFont(size: 10).foregroundStyle(.secondary)
                            }
                            .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            output
                        }
                        .frame(height: 200)
                    }
                    HStack {
                        Button("Clear") { viewModel.clear(); inputFocused = true }
                        if viewModel.canPrepare { Button("Download Languages…") { viewModel.prepareLanguages() } }
                        Spacer()
                        Button("Copy Translation", systemImage: "doc.on.doc") { viewModel.copy() }
                            .disabled(viewModel.result == nil || viewModel.isBusy)
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                        if viewModel.isTranslating || viewModel.isPreparing {
                            Button("Cancel") { viewModel.cancel() }
                        } else if viewModel.isWordMode {
                            Button("Translate") { viewModel.translate() }
                                .buttonStyle(.borderedProminent).disabled(!viewModel.canTranslate)
                                .keyboardShortcut(.defaultAction)
                        } else {
                            Button("Translate") { viewModel.translate() }
                                .buttonStyle(.borderedProminent).disabled(!viewModel.canTranslate)
                                .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                    Text(availabilityText).commandlyFont(size: 10).foregroundStyle(.secondary)
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .commandlyFont(size: 11).foregroundStyle(.orange)
                    }
                }
                .padding(density.spacing(.md))
            }
            .background(LauncherPalette.detail)
        }
        .background {
            if let nativeBridge { NativeTranslationTaskView(bridge: nativeBridge) }
        }
        .task { if viewModel.languages.isEmpty { viewModel.loadLanguages() } }
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
        .onDisappear { viewModel.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Translate text with Apple Translation")
    }

    private var languages: some View {
        HStack {
            Picker("From", selection: $viewModel.sourceLanguageID) {
                Text("Detect Language").tag(String?.none)
                ForEach(viewModel.languages) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden().accessibilityLabel("Source language")
            Button(action: viewModel.swapLanguages) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.plain).disabled(viewModel.sourceLanguageID == nil || viewModel.isBusy)
                .accessibilityLabel("Swap source and target languages")
            Picker("To", selection: $viewModel.targetLanguageID) {
                if viewModel.targetLanguageID.isEmpty { Text("Choose Target Language").tag("") }
                ForEach(viewModel.languages) { Text($0.name).tag($0.id) }
            }
            .labelsHidden().accessibilityLabel("Target language")
            if viewModel.isLoadingLanguages { ProgressView().controlSize(.small).accessibilityLabel("Loading native languages") }
            else {
                Button(action: viewModel.loadLanguages) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel("Refresh supported languages")
            }
        }
        .disabled(viewModel.isLoadingLanguages)
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Translation").commandlyFont(size: 11, weight: .medium)
            if let result = viewModel.result {
                Text("\(result.sourceLanguage.name) → \(result.targetLanguage.name)")
                    .commandlyFont(size: 10).foregroundStyle(.secondary)
                ScrollView { Text(result.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .accessibilityLabel("Translated text")
            } else {
                Spacer()
                if viewModel.isTranslating || viewModel.isPreparing { ProgressView().controlSize(.small) }
                Text("Your translation appears here after you choose Translate.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var availabilityText: String {
        switch viewModel.pairAvailability {
        case .checking: "Checking this language pair…"
        case .installed: "Languages are ready. Translation stays on this device; copying is a separate action."
        case .downloadRequired: "This pair may need language files. Apple asks before downloading. Downloads can continue after you leave."
        case .unsupported: "Apple Translation does not support this pair, including translation to the same language."
        case .automaticSource: "Apple detects the source and may ask you to choose it for a short word. Language downloads require your approval."
        }
    }
}
