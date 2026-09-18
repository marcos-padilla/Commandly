import DesignSystem
import Foundation
import Infrastructure
import SwiftUI

struct WritingToolsView: View {
    @Bindable var viewModel: WritingToolsViewModel
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var focusedInput: Bool
    @State private var isVisible = false
    @State private var focusRequestID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyBackButton(action: viewModel.goBack)
                Image(systemName: "text.badge.checkmark").foregroundStyle(BrandPalette.accentSoft)
                Text("Spelling & Grammar").commandlyFont(size: 14, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CommandlyOptionMenu(items: [.init(id: "", title: "Automatic language")]
                    + viewModel.languages.map { .init(id: $0, title: Locale.current.localizedString(forIdentifier: $0) ?? $0) },
                    selectionID: viewModel.languageID, accessibilityLabelText: "Spelling language") {
                        viewModel.languageID = $0.id
                    }
            }.padding(density.spacing(.md)).background(LauncherPalette.chrome).zIndex(2)
            Divider()
            if viewModel.showsInlineInstructions { inlineInstructions }
            else { checker }
        }
        .onAppear { isVisible = true; requestInputFocus() }
        .onChange(of: viewModel.showsInlineInstructions) { _, showsInstructions in
            if showsInstructions { focusRequestID = UUID(); focusedInput = false }
            else { requestInputFocus() }
        }
        .onDisappear { isVisible = false; focusRequestID = UUID(); viewModel.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spelling and grammar checker")
    }

    private var checker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                Text("Check text with the spelling and grammar services available on your Mac.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: density.spacing(.md)) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Original").commandlyFont(size: 11, weight: .semibold)
                        TextEditor(text: $viewModel.input).commandlyFont(size: 12)
                            .focused($focusedInput).frame(minHeight: 150, maxHeight: 210)
                            .accessibilityLabel("Text to check").accessibilityIdentifier("writing-input")
                            .overlay(alignment: .topLeading) {
                                if viewModel.input.isEmpty {
                                    Text("Type or paste text here…").commandlyFont(size: 12).foregroundStyle(.tertiary)
                                        .padding(6).allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Reviewed result").commandlyFont(size: 11, weight: .semibold)
                        TextEditor(text: $viewModel.output).commandlyFont(size: 12)
                            .frame(minHeight: 150, maxHeight: 210)
                            .disabled(viewModel.report == nil || viewModel.isChecking)
                            .accessibilityLabel("Editable correction result").accessibilityIdentifier("writing-output")
                    }
                }
                HStack {
                    if viewModel.isChecking {
                        ProgressView().controlSize(.small)
                        Button("Cancel", action: viewModel.cancelCheck)
                    } else {
                        Button("Check Text", action: viewModel.check).buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(viewModel.canCheck == false)
                    }
                    Button("Use Automatic Suggestions", action: viewModel.useAutomaticSuggestions)
                        .disabled(viewModel.canUseCorrections == false)
                    Spacer()
                    Button("Copy Result", action: viewModel.copyResult).disabled(viewModel.canCopy == false)
                }.buttonStyle(.bordered)
                if let report = viewModel.report {
                    HStack {
                        Text(report.issues.isEmpty ? "No issues returned" : "Suggestions").commandlyFont(size: 12, weight: .semibold)
                        Spacer()
                        Button("Restore Original", action: viewModel.restoreOriginal).buttonStyle(.borderless)
                    }
                    ForEach(report.issues) { issue in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: issue.kind == .grammar ? "text.alignleft" : "character.cursor.ibeam")
                                Text(issue.explanation).commandlyFont(size: 11)
                            }
                            if let range = Range(issue.range.nsRange, in: report.source) {
                                Text(String(report.source[range])).commandlyFont(size: 12, weight: .medium).textSelection(.enabled)
                            }
                            if issue.suggestions.isEmpty {
                                Text("No automatic replacement was provided. Edit the result to correct this issue.")
                                    .commandlyFont(size: 10).foregroundStyle(.secondary)
                            } else {
                                Menu("Choose Replacement") {
                                    ForEach(issue.suggestions, id: \.self) { suggestion in
                                        Button(suggestion.isEmpty ? "Remove" : suggestion) { viewModel.useSuggestion(suggestion, for: issue) }
                                    }
                                }.menuStyle(.borderlessButton).fixedSize().commandlyFont(size: 10)
                                    .accessibilityLabel("Replacement options for this issue")
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if viewModel.input.utf8.count > WritingCorrectionPolicy.maximumInputBytes {
                    Text("Check at most 16 KiB of text at a time.").foregroundStyle(.secondary).commandlyFont(size: 11)
                }
                if viewModel.output.utf8.count > WritingCorrectionPolicy.maximumOutputBytes {
                    Text("Shorten the reviewed result to 64 KiB before copying.").foregroundStyle(.secondary).commandlyFont(size: 11)
                }
                Button("Quick Fix selected text in another app…") { viewModel.showsInlineInstructions = true }
                    .buttonStyle(.borderless).commandlyFont(size: 11)
                Text("Text stays in this session. This tool does not send text to an AI provider or read another app automatically.")
                    .commandlyFont(size: 10).foregroundStyle(.secondary)
            }.padding(density.spacing(.md))
        }.background(LauncherPalette.detail)
    }

    private var inlineInstructions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                Image(systemName: "cursorarrow.and.square.on.square.dashed").commandlyFont(size: 28).foregroundStyle(BrandPalette.accentSoft)
                Text("Quick Fix where you’re writing").commandlyFont(size: 20, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Select text in an editable field, then choose Services → Quick Fix Selection Locally from that app’s menu or the selection’s context menu.")
                Text("Invoking the service applies eligible native spelling and grammar corrections directly to that selection. A brief progress panel offers Cancel. Review the changed text in your editor and use its Undo command where supported.")
                Text("For a keyboard shortcut, open System Settings → Keyboard → Keyboard Shortcuts → Services → Text, enable Quick Fix Selection Locally, and assign an unused shortcut.")
                Text("Some editors do not support text Services. This launcher does not automatically capture their selection. Use this checker and Copy Result for those apps. If the service is missing, run Commandly from Applications and reopen the editor.")
                    .foregroundStyle(.secondary)
                Button("Open Review Checker") { viewModel.showsInlineInstructions = false }
                    .buttonStyle(.borderedProminent)
            }
            .commandlyFont(size: 12)
            .padding(density.spacing(.lg)).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(LauncherPalette.detail)
    }

    private func requestInputFocus() {
        let request = UUID(); focusRequestID = request
        // Defer until the editor has attached after initial presentation or returning from help.
        DispatchQueue.main.async {
            guard isVisible, focusRequestID == request, viewModel.showsInlineInstructions == false else { return }
            focusedInput = true
        }
    }
}
