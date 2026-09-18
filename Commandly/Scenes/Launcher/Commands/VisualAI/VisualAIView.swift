import AIKit
import AppKit
import Infrastructure
import SwiftUI

struct VisualAIView: View {
    @Bindable var model: VisualAIModel
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: model.goBack) { Image(systemName: "chevron.left") }.accessibilityLabel("Back")
                Text("Visual AI").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("AI Settings", action: model.configureAI)
            }
            Picker("Capture area", selection: $model.kind) {
                Text("Full Screen").tag(ScreenshotKind.display)
                Text("Selected Region").tag(ScreenshotKind.region)
            }.pickerStyle(.segmented).disabled(model.isWorking)
            Text(model.kind == .display
                 ? "Choose one full display in the macOS picker. Capture stays local until Send."
                 : "Select a rectangular region. Capture may request Screen Recording access; no image is sent until Send.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if let image = model.image, let preview = NSImage(data: image.data) {
                Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 190)
                    .accessibilityLabel("Exact screenshot image that will be sent")
                HStack {
                    Text("\(image.pixelWidth) × \(image.pixelHeight) · JPEG · \(image.data.count / 1_024) KB").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("Remove Image", action: model.clearImage)
                }
            }
            HStack {
                Button(model.image == nil ? "Capture" : "Capture Again", systemImage: "camera.viewfinder", action: model.capture).disabled(model.isWorking)
                if model.needsPermissionRecovery { Button("Screen Recording Settings", action: model.openScreenSettings) }
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small); Button("Cancel", action: model.cancel) }
            }
            HStack {
                Picker("Send to", selection: $model.selectedID) {
                    Text("Choose an image-capable model").tag(Optional<String>.none)
                    ForEach(model.selections) { Text($0.title).tag(Optional($0.id)) }
                }.disabled(model.isWorking)
                Button("Refresh Models", action: model.loadModels).disabled(model.isWorking || model.isLoading)
            }
            TextField("Ask about this screenshot", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4).disabled(model.isWorking)
            Text("Send shares this image and your question with \(model.selected?.providerName ?? "the selected provider") under your provider account. Screenshots may contain private information. No conversation or image history is saved.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button("Send Screenshot", systemImage: "arrow.up", action: model.send)
                .buttonStyle(.borderedProminent).disabled(!model.canSend).keyboardShortcut(.return, modifiers: [.command])
            if let message = model.message { Text(message).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
            if !model.response.isEmpty {
                ScrollView { Text(model.response).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .frame(minHeight: 90, maxHeight: 220).accessibilityLabel("Visual AI answer")
            }
        }.padding(14).frame(minWidth: 480)
            .task { model.loadModels() }.onDisappear { model.stop() }
            .accessibilityElement(children: .contain).accessibilityLabel("Visual AI screenshot review and send")
    }
}
