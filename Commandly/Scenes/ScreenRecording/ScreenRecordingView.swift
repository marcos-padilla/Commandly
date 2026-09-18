import AVKit
import DesignSystem
import Infrastructure
import SwiftUI

struct ScreenRecordingView: View {
    @Bindable var model: ScreenRecordingModel
    @Environment(\.commandlyTextScale) private var textScale
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let label = model.sessionLabel { Text(label).commandlyFont(size: 11, weight: .medium).foregroundStyle(.orange) }
            if model.isCompact { recordingControls }
            else {
                HStack(spacing: 12) {
                    Image(systemName: "record.circle").font(.system(size: 28, weight: .light)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.artifact == nil ? "Screen Recording" : "Your recording").commandlyFont(size: 22, weight: .semibold)
                        Text(model.artifact == nil ? "Choose the content. Keep the result local." : "Review your video before saving it.")
                            .commandlyFont(size: 12).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if model.artifact != nil { review }
                else if model.phase == .setup { setup }
                else { pending }
                if let message = model.message {
                    Text(message).commandlyFont(size: 13).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("screen-recording.message")
                }
            }
        }
        .commandlyFont(size: 13)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-recording.window")
        .onChange(of: model.artifact?.draft.id, initial: true) {
            player?.pause()
            player = model.artifact.map { AVPlayer(url: $0.draft.url) }
        }
        .onDisappear { player?.pause(); player = nil }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Record").foregroundStyle(.secondary)
                    Picker("Record", selection: $model.options.source) {
                        Text("One window").tag(ScreenRecordingSource.window)
                        Text("One display").tag(ScreenRecordingSource.display)
                    }.labelsHidden().pickerStyle(.segmented)
                }
                GridRow {
                    Text("Audio").foregroundStyle(.secondary)
                    Picker("Audio", selection: $model.options.audio) {
                        Text("Off").tag(ScreenRecordingAudio.none)
                        Text("System audio").tag(ScreenRecordingAudio.systemAudio)
                    }.labelsHidden().pickerStyle(.segmented)
                }
                GridRow {
                    Text("Video").foregroundStyle(.secondary)
                    HStack {
                        Picker("File format", selection: $model.options.container) {
                            Text("MP4").tag(ScreenRecordingContainer.mp4); Text("MOV").tag(ScreenRecordingContainer.mov)
                        }.labelsHidden()
                        Picker("Video codec", selection: $model.options.codec) {
                            Text("H.264").tag(ScreenRecordingCodec.h264); Text("HEVC").tag(ScreenRecordingCodec.hevc)
                        }.labelsHidden()
                        Picker("Maximum resolution", selection: $model.options.resolution) {
                            Text("1080p").tag(ScreenRecordingResolution.fullHD); Text("720p").tag(ScreenRecordingResolution.hd720)
                        }.labelsHidden()
                    }
                }
            }
            Toggle("Include pointer", isOn: $model.options.showsCursor).toggleStyle(.checkbox)
            Text(model.options.source == .display
                 ? "A display recording includes everything visible on that display, including these controls. Move them before you choose the display."
                 : "The macOS picker asks you to share one window. Protected content may not be available.")
                .commandlyFont(size: 13).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("\(model.audioDescription). Up to 10 minutes · 30 fps · Automatic size limit.")
                .commandlyFont(size: 11).foregroundStyle(.secondary)
            HStack {
                Text("Nothing is captured until you choose content.").commandlyFont(size: 11).foregroundStyle(.secondary)
                Spacer()
                Button("Choose & Record…") { model.start() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("screen-recording.start")
            }.padding(.top, 4)
        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "record.circle.fill").foregroundStyle(.red).accessibilityHidden(true)
                Text(model.phase == .recording ? "Recording" : "Finishing recording")
                    .commandlyFont(size: 14, weight: .semibold)
                Spacer()
                Text(model.durationText).font(.system(size: 23 * textScale, weight: .medium, design: .monospaced))
                    .accessibilityLabel("Elapsed time \(model.durationText)")
            }
            HStack {
                Text(model.audioDescription).commandlyFont(size: 13).foregroundStyle(.secondary)
                Spacer()
                Text(model.sizeText).commandlyFont(size: 13).monospacedDigit().foregroundStyle(.secondary)
            }
            if let message = model.message { Text(message).commandlyFont(size: 11).foregroundStyle(.secondary) }
            HStack {
                if model.phase == .recording {
                    Button("Cancel Recording") { model.discard() }.buttonStyle(.borderless)
                    Spacer()
                    Button("Stop & Review") { model.stop() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    ProgressView().controlSize(.small)
                    Text(model.phase == .cancelling ? "Stopping before removing the video…" : "Waiting for macOS to finish the video…")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                    Spacer()
                    if model.needsStopRetry || model.phase == .cancelling {
                        Button("Retry Stop") { model.stop() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenRecordingPlayerView(player: player).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Recorded video playback")
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.durationText) · \(model.sizeText)").commandlyFont(size: 13).monospacedDigit()
                    Text(model.audioDescription).commandlyFont(size: 11).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Discard") { player?.pause(); model.discard() }.disabled(model.phase == .exporting)
                Button(model.phase == .exporting ? "Saving…" : "Save Video…") { player?.pause(); model.requestExport() }
                    .disabled(model.phase != .review).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("screen-recording.save")
            }
        }
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.phase != .discardFailed {
                ProgressView(model.phase == .preparing ? "Preparing private recording storage…" : "Choose a window or display in the macOS picker…")
            }
            Text("\(model.audioDescription). The microphone is never recorded.").commandlyFont(size: 13).foregroundStyle(.secondary)
            Button(model.phase == .discardFailed ? "Retry Discard" : "Cancel") { model.discard() }
        }.frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }
}

/// Direct native AVPlayerView ownership avoids the SwiftUI VideoPlayer overlay's runtime
/// superclass metadata dependency and gives the review surface explicit teardown semantics.
private struct ScreenRecordingPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsSharingServiceButton = false
        view.allowsVideoFrameAnalysis = false
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player?.pause(); view.player = player }
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
