import AppKit
import DesignSystem
import Infrastructure
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundRemoverView: View {
    @Bindable var viewModel: BackgroundRemoverViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LauncherPalette.detail)
        }
        .fileImporter(
            isPresented: $viewModel.showsImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { selection in
            guard case .success(let urls) = selection, let url = urls.first else { return }
            viewModel.process(url)
        }
        .fileExporter(
            isPresented: $viewModel.showsFileExporter,
            document: exportDocument,
            contentType: .png,
            defaultFilename: viewModel.suggestedFilename
        ) { result in
            viewModel.exportCompleted(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            viewModel.process(url)
            return true
        }
        .accessibilityLabel("Background Remover")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            Image(systemName: "person.crop.rectangle")
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: density.iconSize, height: density.iconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Background Remover")
                    .commandlyFont(size: 15, weight: .semibold)
                Text("Private, on-device foreground separation")
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("On-device AI", systemImage: "lock.shield.fill")
                .commandlyFont(size: 9.5, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, density.spacing(.sm))
                .padding(.vertical, density.spacing(.xs))
                .background(Color.primary.opacity(0.055))
                .clipShape(Capsule())
                .accessibilityHint("Images never leave this Mac")
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            emptyState
        case .processing(let filename):
            processingState(filename: filename)
        case .completed(let result):
            completedState(result)
        case .failed(let filename, let message):
            failureState(filename: filename, message: message)
        }
    }

    private var emptyState: some View {
        VStack(spacing: density.spacing(.lg)) {
            VStack(spacing: density.spacing(.sm)) {
                Image(systemName: "photo.badge.arrow.down")
                    .commandlyFont(size: 42, weight: .medium)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Drop an image here")
                    .commandlyFont(size: 19, weight: .semibold)

                Text("Commandly detects the foreground locally and creates a transparent PNG.")
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }

            Button("Choose Image…", systemImage: "photo.on.rectangle") {
                viewModel.perform(BackgroundRemoverActionID.chooseImage)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

            Label("PNG, JPEG, HEIC, TIFF, and other macOS image formats", systemImage: "info.circle")
                .commandlyFont(size: 9.5)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(density.spacing(.xl))
        .contentShape(Rectangle())
        .accessibilityHint("Choose or drop an image to remove its background")
    }

    private func processingState(filename: String) -> some View {
        VStack(spacing: density.spacing(.md)) {
            ProgressView()
                .controlSize(.large)
            Text("Separating foreground…")
                .commandlyFont(size: 17, weight: .semibold)
            Text(filename)
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("The image stays on this Mac.")
                .commandlyFont(size: 9.5)
                .foregroundStyle(.tertiary)
            Button("Cancel") {
                viewModel.perform(BackgroundRemoverActionID.cancel)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(density.spacing(.xl))
    }

    private func completedState(_ result: BackgroundRemovalResult) -> some View {
        VStack(spacing: density.spacing(.md)) {
            HStack(spacing: density.spacing(.md)) {
                imagePane(
                    title: "Original",
                    data: result.sourcePreviewPNGData,
                    showsTransparency: false
                )
                imagePane(
                    title: "Transparent",
                    data: result.transparentPreviewPNGData,
                    showsTransparency: true
                )
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: density.spacing(.sm)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.sourceFilename)
                        .commandlyFont(size: 11, weight: .semibold)
                        .lineLimit(1)
                    Text("\(result.pixelWidth) × \(result.pixelHeight) px • PNG with transparency")
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Choose Another", systemImage: "arrow.triangle.2.circlepath") {
                    viewModel.perform(BackgroundRemoverActionID.chooseImage)
                }
                .buttonStyle(.bordered)

                Button("Save PNG…", systemImage: "square.and.arrow.down") {
                    viewModel.perform(BackgroundRemoverActionID.savePNG)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(density.spacing(.md))
    }

    private func failureState(filename: String, message: String) -> some View {
        VStack(spacing: density.spacing(.md)) {
            Image(systemName: "exclamationmark.triangle")
                .commandlyFont(size: 34, weight: .medium)
                .foregroundStyle(Color(nsColor: .systemOrange))
                .accessibilityHidden(true)
            Text("Couldn’t remove the background")
                .commandlyFont(size: 17, weight: .semibold)
            Text(filename)
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(message)
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 410)
            Button("Choose Another Image…", systemImage: "photo.on.rectangle") {
                viewModel.perform(BackgroundRemoverActionID.chooseImage)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(density.spacing(.xl))
    }

    private func imagePane(title: String, data: Data, showsTransparency: Bool) -> some View {
        VStack(alignment: .leading, spacing: density.spacing(.xs)) {
            Text(title)
                .commandlyFont(size: 10, weight: .semibold)
                .foregroundStyle(.secondary)

            ZStack {
                if showsTransparency {
                    TransparencyGrid()
                } else {
                    Color.primary.opacity(0.035)
                }

                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(density.spacing(.sm))
                        .accessibilityLabel(title + " image preview")
                } else {
                    Image(systemName: "photo")
                        .commandlyFont(size: 28)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(title + " preview unavailable")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BackgroundRemovalPNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

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

private struct TransparencyGrid: View {
    private let squareSize: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(Color.primary.opacity(0.055)))
                }
            }
        }
        .background(Color.primary.opacity(0.018))
        .accessibilityHidden(true)
    }
}

private extension BackgroundRemoverView {
    var exportDocument: BackgroundRemovalPNGDocument? {
        viewModel.result.map { BackgroundRemovalPNGDocument(data: $0.transparentPNGData) }
    }
}
