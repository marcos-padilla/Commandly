import AppKit
import DesignSystem
import Infrastructure
import SwiftUI
import UniformTypeIdentifiers

struct CameraView: View {
    @Bindable var viewModel: CameraViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.sm)) {
                CommandlyBackButton(action: viewModel.goBack)
                Image(systemName: "camera").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera").commandlyFont(size: 15, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text("A quick look, a photo to keep").commandlyFont(size: 10).foregroundStyle(.secondary)
                }
                Spacer()
                Label(cameraIsActive ? "Camera on" : "Camera off", systemImage: cameraIsActive ? "video.fill" : "video.slash")
                    .commandlyFont(size: 10, weight: .medium)
                    .foregroundStyle(cameraIsActive ? Color.green : Color.secondary)
                    .accessibilityLabel(cameraIsActive ? "Camera is on. No audio." : "Camera is off")
            }
            .padding(density.spacing(.md))
            Rectangle().fill(LauncherPalette.separator).frame(height: 1)
            ScrollView {
                VStack(spacing: density.spacing(.md)) {
                    if let photo = viewModel.photo {
                        review(photo)
                    } else if cameraIsActive || viewModel.isBusy {
                        preview
                    } else {
                        idle
                    }
                    if case .failed = viewModel.state, let status = viewModel.statusMessage {
                        Label(status, systemImage: "exclamationmark.triangle")
                            .commandlyFont(size: 11).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(density.spacing(.md))
            }
            .background(LauncherPalette.detail)
        }
        .fileExporter(
            isPresented: $viewModel.showsFileExporter,
            document: viewModel.photo.map { CameraPhotoDocument(data: $0.pngData) },
            contentType: .png, defaultFilename: viewModel.suggestedFilename,
            onCompletion: viewModel.exportCompleted
        )
        .onDisappear { viewModel.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera preview and photo review")
    }

    private var cameraIsActive: Bool {
        viewModel.state == .previewing || viewModel.state == .capturing
    }

    private var idle: some View {
        VStack(spacing: density.spacing(.md)) {
            Image(systemName: "camera.aperture").commandlyFont(size: 44).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Ready when you are").commandlyFont(size: 20, weight: .semibold)
            Text("Start your camera to check your appearance or take a photo. Commandly asks for Camera access only when you start.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
            if viewModel.needsSettingsRecovery {
                Button("Open Camera Settings", systemImage: "gear") { viewModel.perform(CameraActionID.openSettings) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("Try Start Camera Again") { viewModel.start() }
            } else {
                Button("Start Camera", systemImage: "video") { viewModel.start() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Video only · Nothing uploaded · Save or copy only when you choose")
                .commandlyFont(size: 10).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 270)
    }

    private var preview: some View {
        VStack(spacing: density.spacing(.sm)) {
            ZStack {
                Color.black.opacity(0.86)
                if let frame = viewModel.frame, let image = CameraFrameRenderer.image(from: frame) {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit()
                        .scaleEffect(x: viewModel.mirrorsImage ? -1 : 1, y: 1)
                        .accessibilityLabel("Live camera preview")
                } else {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(viewModel.state == .requestingPermission ? "Waiting for Camera access…" : "Preparing preview…")
                            .commandlyFont(size: 11).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                if viewModel.devices.count > 1 {
                    Picker("Camera", selection: Binding(
                        get: { viewModel.selectedDeviceID ?? "" }, set: viewModel.selectDevice
                    )) {
                        ForEach(viewModel.devices) { device in Text(device.name).tag(device.id) }
                    }
                    .pickerStyle(.menu).disabled(viewModel.isBusy)
                } else if let device = viewModel.devices.first {
                    Text(device.name).lineLimit(1).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Mirror preview and photo", isOn: $viewModel.mirrorsImage)
                    .toggleStyle(.checkbox).disabled(viewModel.isBusy)
                    .accessibilityHint("Keeps the saved photo aligned with the preview")
            }
            .commandlyFont(size: 11)
            HStack {
                Button(viewModel.isBusy ? "Cancel" : "Stop Camera", systemImage: "stop.circle") { viewModel.stop() }
                Spacer()
                Button("Take Photo", systemImage: "camera") { viewModel.takePhoto() }
                    .buttonStyle(.borderedProminent).disabled(viewModel.canCapture == false)
                    .keyboardShortcut(.defaultAction)
            }
            Text("The camera stops after capture. Your photo stays here until you save, copy, retake, or leave.")
                .commandlyFont(size: 10).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func review(_ photo: CameraPhoto) -> some View {
        VStack(spacing: density.spacing(.sm)) {
            if let image = NSImage(data: photo.previewPNGData) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Captured photo for review")
            }
            HStack {
                Label("Camera off", systemImage: "video.slash").foregroundStyle(.secondary)
                Spacer()
                Text("PNG · \(photo.pixelWidth) × \(photo.pixelHeight)").foregroundStyle(.secondary)
            }
            .commandlyFont(size: 11)
            HStack {
                Button("Retake") { viewModel.start() }
                Button("Discard") { viewModel.stop() }
                Spacer()
                Button(viewModel.isCopying ? "Copying…" : "Copy Photo") { viewModel.copyPhoto() }.disabled(viewModel.isCopying)
                Button("Save Photo…", systemImage: "square.and.arrow.down") { viewModel.perform(CameraActionID.save) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            if let status = viewModel.statusMessage {
                Text(status).commandlyFont(size: 10).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CameraPhotoDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
