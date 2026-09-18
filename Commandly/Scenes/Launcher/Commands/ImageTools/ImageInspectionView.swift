import AppKit
import DesignSystem
import Infrastructure
import SwiftUI

struct ImageInspectionView: View {
    @Bindable var viewModel: ImageInspectionViewModel
    let mode: ImageToolsMode
    let source: ImageConversionSource?
    let isLoadingSource: Bool
    let chooseImage: () -> Void
    let retry: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: density.spacing(.md)) {
            if let source {
                sourceSummary(source)
                if viewModel.isWorking {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(viewModel.statusMessage ?? "Reading image…")
                        Spacer()
                        Button("Cancel", action: viewModel.cancel)
                    }
                    .commandlyFont(size: 11)
                    .padding(.vertical, density.spacing(.lg))
                } else if let result = viewModel.result {
                    if mode == .text { textResult(result) } else { qrResult(result) }
                    if result.isTruncated {
                        Label("Some results were omitted to stay within the output limits. Try a closer crop for the remaining content.",
                              systemImage: "info.circle")
                            .commandlyFont(size: 10).foregroundStyle(.secondary)
                    }
                } else {
                    Button(mode == .text ? "Extract Text" : "Decode QR", action: retry)
                        .buttonStyle(.borderedProminent)
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .commandlyFont(size: 11).foregroundStyle(.orange)
                }
                actions
            } else if isLoadingSource == false {
                emptyState
            }
        }
        .sheet(item: $viewModel.pendingURLReview) { review in
            linkReview(review)
        }
    }

    private var emptyState: some View {
        VStack(spacing: density.spacing(.md)) {
            Image(systemName: mode == .text ? "text.viewfinder" : "qrcode.viewfinder")
                .commandlyFont(size: 42).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(mode == .text ? "Read the text in an image" : "See what a QR code contains")
                .commandlyFont(size: 20, weight: .semibold)
            Text(mode == .text
                 ? "Choose or drop one image. Review and edit the recognized text before copying."
                 : "Choose or drop one image. QR content appears for review and stays local until you choose an action.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
            Button("Choose Image…", systemImage: "photo.on.rectangle", action: chooseImage)
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("Still images up to 64 MB and 40 megapixels · No camera access")
                .commandlyFont(size: 10).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 265)
    }

    private func sourceSummary(_ source: ImageConversionSource) -> some View {
        HStack(spacing: density.spacing(.md)) {
            if let preview = NSImage(data: source.previewPNGData) {
                Image(nsImage: preview).resizable().scaledToFit().frame(width: 76, height: 58)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Selected source image preview")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(source.filename).commandlyFont(size: 12, weight: .semibold).lineLimit(1)
                Text("\(source.pixelWidth) × \(source.pixelHeight) pixels · On-device Vision")
                    .commandlyFont(size: 10).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func textResult(_ result: ImageRecognitionResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Review recognized text").commandlyFont(size: 12, weight: .semibold)
            TextEditor(text: $viewModel.reviewedText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 165, maxHeight: 230)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(LauncherPalette.separator, lineWidth: 1)
                }
                .accessibilityLabel("Recognized text, editable before copying")
                .accessibilityHint("Recognition can make mistakes. Check names, numbers, and reading order.")
            Text(result.text.isEmpty
                 ? "No readable text found. Try a clearer image."
                 : "Check names, numbers, and reading order. You can edit this text before copying.")
                .commandlyFont(size: 10).foregroundStyle(.secondary)
        }
    }

    private func qrResult(_ result: ImageRecognitionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.qrPayloads.isEmpty {
                Label(viewModel.statusMessage ?? "No QR code found.", systemImage: "qrcode")
                    .commandlyFont(size: 12).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                if result.qrPayloads.count > 1 {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(result.qrPayloads.indices, id: \.self) { index in
                                Button { viewModel.selectPayload(at: index) } label: {
                                    HStack {
                                        Image(systemName: viewModel.selectedPayloadIndex == index ? "checkmark.circle.fill" : "circle")
                                        Text("QR Code \(index + 1)").fontWeight(.medium)
                                        Text(verbatim: result.qrPayloads[index]).lineLimit(1).foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .background(viewModel.selectedPayloadIndex == index ? Color.accentColor.opacity(0.12) : .clear,
                                                in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("QR Code \(index + 1)\(viewModel.selectedPayloadIndex == index ? ", selected" : "")")
                            }
                        }
                    }
                    .frame(maxHeight: 105)
                }
                Text("QR content").commandlyFont(size: 12, weight: .semibold)
                ScrollView {
                    Text(verbatim: viewModel.selectedPayload ?? "")
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(minHeight: 80, maxHeight: 150)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("Decoded QR content")
                Text("QR contents are plain text here. Only reviewed HTTP or HTTPS links can be opened.")
                    .commandlyFont(size: 10).foregroundStyle(.secondary)
            }
            if result.nonTextQRCodeCount > 0 && result.qrPayloads.isEmpty == false {
                Text("\(result.nonTextQRCodeCount) additional QR code(s) did not contain readable text.")
                    .commandlyFont(size: 10).foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Choose Another…", action: chooseImage)
            if viewModel.isWorking == false {
                Button("Read Again", action: retry).disabled(viewModel.isPerformingAction)
            }
            Spacer()
            if viewModel.canReviewLink {
                Button("Review Link…", systemImage: "link", action: viewModel.reviewSelectedLink)
                    .accessibilityHint("Shows the full web address before a separate Open Link action")
            }
            Button(mode == .text ? "Copy Text" : "Copy QR Content", systemImage: "doc.on.doc", action: viewModel.copySelection)
                .buttonStyle(.borderedProminent).disabled(viewModel.canCopy == false)
        }
        .commandlyFont(size: 11)
    }

    private func linkReview(_ review: ImageQRURLReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Review Web Link", systemImage: "link").font(.headline)
            Text(verbatim: review.host).font(.title3.weight(.semibold)).textSelection(.enabled)
            ScrollView {
                Text(verbatim: review.url.absoluteString).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 125)
            Text("Open Link sends this address to your default browser. Check the destination before continuing.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { viewModel.pendingURLReview = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open Link", systemImage: "arrow.up.forward", action: viewModel.openReviewedLink)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 440)
        .accessibilityElement(children: .contain)
    }
}
