import AppKit
import DesignSystem
import Infrastructure
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotView: View {
    @Bindable var viewModel: ScreenshotViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.sm)) {
                CommandlyBackButton(action: viewModel.goBack)
                Image(systemName: "camera.viewfinder").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot").commandlyFont(size: 15, weight: .semibold).accessibilityAddTraits(.isHeader)
                    Text("Choose a moment to keep").commandlyFont(size: 10).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Local only", systemImage: "lock.shield").commandlyFont(size: 10).foregroundStyle(.secondary)
            }
            .padding(density.spacing(.md))
            Rectangle().fill(LauncherPalette.separator).frame(height: 1)
            ScrollView {
                VStack(spacing: density.spacing(.md)) {
                    if let image = viewModel.image { review(image) }
                    else if viewModel.isCapturing {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.small)
                            Text(viewModel.statusMessage ?? "Preparing screenshot…").multilineTextAlignment(.center)
                            Button("Cancel") { viewModel.stop() }
                        }
                        .commandlyFont(size: 12).frame(maxWidth: .infinity, minHeight: 280)
                    } else { selection }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .commandlyFont(size: 11).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(density.spacing(.md))
            }
            .background(LauncherPalette.detail)
        }
        .fileExporter(isPresented: $viewModel.showsFileExporter,
                      document: viewModel.image.map { ScreenshotDocument(data: $0.pngData) },
                      contentType: .png, defaultFilename: viewModel.suggestedFilename,
                      onCompletion: viewModel.exportCompleted)
        .onDisappear { viewModel.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot selection and review")
    }

    private var selection: some View {
        VStack(spacing: density.spacing(.md)) {
            Image(systemName: "viewfinder").commandlyFont(size: 40).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Capture exactly what you choose").commandlyFont(size: 19, weight: .semibold)
            Picker("Screenshot selection", selection: $viewModel.kind) {
                Text("Region").tag(ScreenshotKind.region)
                Text("Window").tag(ScreenshotKind.window)
                Text("Display").tag(ScreenshotKind.display)
            }
            .pickerStyle(.segmented).frame(maxWidth: 400)
            Text(viewModel.kind == .region
                 ? "Drag to select a region across your displays. Region capture needs Screen Recording access; Commandly requests it only when you choose to capture."
                 : "The macOS picker shares only the window or display you select. A separate Screen Recording grant is not required for this selection.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 410)
            Toggle("Include pointer", isOn: $viewModel.showsCursor).toggleStyle(.checkbox).commandlyFont(size: 11)
            HStack {
                if viewModel.needsSettingsRecovery {
                    Button("Open Screen Recording Settings") { viewModel.perform(ScreenshotActionID.openSettings) }
                }
                Button("Choose and Capture", systemImage: "camera.viewfinder") { viewModel.capture() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Review before copying or saving. No recording, upload, or AI request.")
                .commandlyFont(size: 10).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func review(_ image: ScreenshotImage) -> some View {
        VStack(spacing: density.spacing(.sm)) {
            if let preview = NSImage(data: image.previewPNGData) {
                Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 210)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Screenshot for review")
            }
            HStack {
                Text("\(image.kind.rawValue.capitalized) · PNG")
                Spacer()
                Text("\(image.pixelWidth) × \(image.pixelHeight)").monospacedDigit()
            }
            .commandlyFont(size: 11).foregroundStyle(.secondary)
            HStack {
                Button("New Screenshot") { viewModel.stop() }
                Spacer()
                Button(viewModel.isOpeningAnnotation ? "Opening CleanShot X…" : "Open in CleanShot X", systemImage: "pencil.and.outline") {
                    viewModel.openInCleanShot()
                }
                .disabled(viewModel.isReviewActionBusy)
                .help("Requires installed CleanShot X 3.8.1 or later. Sends only this reviewed PNG to its annotation editor.")
                Button("Save…", systemImage: "square.and.arrow.down") { viewModel.perform(ScreenshotActionID.save) }
                    .disabled(viewModel.isReviewActionBusy)
                Button(viewModel.isCopying ? "Copying…" : "Copy Screenshot", systemImage: "doc.on.doc") { viewModel.copy() }
                    .buttonStyle(.borderedProminent).disabled(viewModel.isReviewActionBusy)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Open in CleanShot X sends this image to its local editor. Commandly’s temporary copy expires after ten minutes while it runs.")
                .commandlyFont(size: 10).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScreenshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
