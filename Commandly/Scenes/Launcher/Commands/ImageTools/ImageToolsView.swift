import AppKit
import DesignSystem
import Infrastructure
import SwiftUI
import UniformTypeIdentifiers

struct ImageToolsView: View {
    @Bindable var viewModel: ImageToolsViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.sm)) {
                CommandlyBackButton(action: viewModel.goBack)
                Image(systemName: "photo.badge.arrow.down").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image Tools").commandlyFont(size: 15, weight: .semibold)
                    Text("A fresh image, made on your Mac").commandlyFont(size: 10).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Local processing", systemImage: "lock.shield").commandlyFont(size: 10).foregroundStyle(.secondary)
            }
            .padding(density.spacing(.md))
            Rectangle().fill(LauncherPalette.separator).frame(height: 1)
            if viewModel.inspection != nil {
                Picker("Image tool", selection: $viewModel.mode) {
                    ForEach(ImageToolsMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, density.spacing(.md))
                .padding(.vertical, density.spacing(.sm))
                .accessibilityHint("Choose image conversion, text extraction, or QR decoding")
            }
            ScrollView {
                VStack(spacing: density.spacing(.md)) {
                    if viewModel.mode != .convert, let inspection = viewModel.inspection {
                        ImageInspectionView(
                            viewModel: inspection,
                            mode: viewModel.mode,
                            source: viewModel.source,
                            isLoadingSource: viewModel.isWorking,
                            chooseImage: { viewModel.perform(ImageToolsActionID.choose) },
                            retry: viewModel.analyzeCurrentImage
                        )
                    } else if let source = viewModel.source {
                        workspace(source)
                    } else if viewModel.isWorking == false {
                        emptyState
                    }
                    if viewModel.isWorking {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(viewModel.statusMessage ?? "Processing image…")
                            Spacer()
                            Button("Cancel") { viewModel.perform(ImageToolsActionID.cancel) }
                        }
                        .commandlyFont(size: 11)
                        .accessibilityElement(children: .contain)
                    }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .commandlyFont(size: 11)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Image Tools error: \(error)")
                    }
                }
                .padding(density.spacing(.md))
                .frame(maxWidth: .infinity)
            }
            .background(LauncherPalette.detail)
        }
        .fileImporter(isPresented: $viewModel.showsImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) {
            viewModel.importCompleted($0)
        }
        .fileExporter(
            isPresented: $viewModel.showsFileExporter,
            document: viewModel.result.map { ImageToolsDocument(data: $0.data) },
            contentType: outputType,
            defaultFilename: viewModel.suggestedFilename,
            onCompletion: viewModel.exportCompleted
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, url.isFileURL else { return false }
            viewModel.load(url)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image Tools")
    }

    private var emptyState: some View {
        VStack(spacing: density.spacing(.md)) {
            Image(systemName: "photo.stack").commandlyFont(size: 42).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Give your image a new format").commandlyFont(size: 20, weight: .semibold)
            Text("Drop one still image here to convert, resize, or rotate it. Your original stays untouched.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
            Button("Choose Image…", systemImage: "photo.on.rectangle") { viewModel.perform(ImageToolsActionID.choose) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("PNG · JPEG · HEIC · TIFF and other macOS image inputs\nUp to 64 MB and 40 megapixels")
                .commandlyFont(size: 10).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 285)
        .contentShape(Rectangle())
    }

    private func workspace(_ source: ImageConversionSource) -> some View {
        VStack(spacing: density.spacing(.md)) {
            HStack(spacing: density.spacing(.md)) {
                preview(title: "Original", data: source.previewPNGData, dimensions: "\(source.pixelWidth) × \(source.pixelHeight)")
                if let result = viewModel.result {
                    preview(title: result.format.title + " output", data: result.previewPNGData, dimensions: "\(result.pixelWidth) × \(result.pixelHeight) · \(ByteCountFormatter.string(fromByteCount: Int64(result.data.count), countStyle: .file))")
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle").commandlyFont(size: 28).accessibilityHidden(true)
                        Text("Your converted preview appears here").commandlyFont(size: 11).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text(source.filename).commandlyFont(size: 11, weight: .medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            controls.disabled(viewModel.isWorking)
            HStack {
                Button("Choose Another…") { viewModel.perform(ImageToolsActionID.choose) }
                Spacer()
                if viewModel.result != nil {
                    Button("Save Image…", systemImage: "square.and.arrow.down") { viewModel.perform(ImageToolsActionID.save) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Convert Image", systemImage: "arrow.triangle.2.circlepath") { viewModel.convert() }
                        .buttonStyle(.borderedProminent).disabled(viewModel.canConvert == false)
                }
            }
            Text("Source location, camera details, and other source metadata are removed from exported images.")
                .commandlyFont(size: 9.5).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            HStack {
                Picker("Output", selection: $viewModel.format) {
                    ForEach(viewModel.supportedFormats) { format in Text(format.title).tag(format) }
                }
                .pickerStyle(.menu)
                Spacer(minLength: 20)
                Button("Rotate 90°", systemImage: "rotate.right") {
                    viewModel.clockwiseQuarterTurns = (viewModel.clockwiseQuarterTurns + 1) % 4
                }
                .accessibilityHint("Rotates the output clockwise. Current rotation \(viewModel.clockwiseQuarterTurns * 90) degrees.")
                Text("\(viewModel.clockwiseQuarterTurns * 90)°").monospacedDigit().frame(width: 35)
            }
            HStack {
                Toggle("Resize, keeping proportions", isOn: $viewModel.resizesImage).toggleStyle(.checkbox)
                if viewModel.resizesImage {
                    TextField("Longest edge", text: $viewModel.longestEdgeText)
                        .textFieldStyle(.roundedBorder).frame(width: 78)
                        .accessibilityLabel("Longest edge in pixels, from 1 to 16,384")
                    Text("px").foregroundStyle(.secondary)
                }
                Spacer()
            }
            if viewModel.resizesImage && viewModel.options == nil {
                Text("Enter a longest edge from 1 to 16,384 pixels.").foregroundStyle(.orange)
            }
            if viewModel.format.preservesTransparency == false {
                Text("Transparent areas become white. \(viewModel.format.title) uses high-quality lossy compression.")
                    .foregroundStyle(.secondary)
            }
        }
        .commandlyFont(size: 11)
        .padding(density.spacing(.sm))
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private func preview(title: String, data: Data, dimensions: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).commandlyFont(size: 11, weight: .semibold)
            ZStack {
                ImageToolsTransparencyGrid()
                if let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().padding(8).accessibilityLabel(title + " preview")
                } else {
                    Text("Preview unavailable").commandlyFont(size: 11)
                }
            }
            .frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 10))
            Text(dimensions).commandlyFont(size: 10).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var outputType: UTType {
        switch viewModel.result?.format ?? viewModel.format {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }
}

private struct ImageToolsTransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            for row in 0..<Int(ceil(size.height / 12)) {
                for column in 0..<Int(ceil(size.width / 12)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: column * 12, y: row * 12, width: 12, height: 12)), with: .color(.primary.opacity(0.07)))
                }
            }
        }
        .background(.primary.opacity(0.025)).accessibilityHidden(true)
    }
}

private struct ImageToolsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg, .heic, .tiff] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
