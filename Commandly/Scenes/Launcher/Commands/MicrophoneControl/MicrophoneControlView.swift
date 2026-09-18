import DesignSystem
import Infrastructure
import SwiftUI

struct MicrophoneControlView: View {
    @Bindable var viewModel: MicrophoneControlViewModel
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
        .onAppear(perform: viewModel.start)
        .onDisappear(perform: viewModel.stop)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Microphone Control")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            Image(systemName: "mic.fill")
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: density.iconSize, height: density.iconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Microphone Control")
                    .commandlyFont(size: 14, weight: .semibold)
                Text(viewModel.state?.deviceName ?? "Default input device")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing microphone status")
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.state == nil, viewModel.errorMessage == nil {
            VStack(spacing: density.spacing(.sm)) {
                ProgressView()
                    .controlSize(.regular)
                Text("Checking the default microphone…")
                    .commandlyFont(size: 12, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage = viewModel.errorMessage, viewModel.state == nil {
            statusPane(
                systemImage: "exclamationmark.triangle.fill",
                color: SemanticColors.color(for: .danger),
                title: "Microphone Status Unavailable",
                message: errorMessage,
                buttonTitle: "Try Again",
                buttonAction: { viewModel.refresh() }
            )
        } else if let state = viewModel.state, let isMuted = state.isMuted {
            statusPane(
                systemImage: isMuted ? "mic.slash.fill" : "mic.fill",
                color: isMuted
                    ? SemanticColors.color(for: .danger)
                    : SemanticColors.color(for: .success),
                title: isMuted ? "Microphone Off" : "Microphone On",
                message: statusMessage(forMutedState: isMuted, canChange: state.canChangeMute),
                buttonTitle: state.canChangeMute ? viewModel.primaryActionTitle : nil,
                buttonAction: viewModel.toggleMute
            )
        } else if let state = viewModel.state {
            statusPane(
                systemImage: "mic.slash.circle.fill",
                color: Color(nsColor: .systemOrange),
                title: "Mute Control Unavailable",
                message: "\(state.deviceName) does not expose a system-wide mute control to macOS.",
                buttonTitle: nil,
                buttonAction: {}
            )
        }
    }

    private func statusPane(
        systemImage: String,
        color: Color,
        title: String,
        message: String,
        buttonTitle: String?,
        buttonAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: density.spacing(.lg)) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 116, height: 116)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1)
                    .frame(width: 116, height: 116)
                Image(systemName: systemImage)
                    .commandlyFont(size: 42, weight: .medium)
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }

            VStack(spacing: density.spacing(.xs)) {
                Text(title)
                    .commandlyFont(size: 22, weight: .semibold)
                Text(message)
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 410)
            }

            if let buttonTitle {
                Button(action: buttonAction) {
                    HStack(spacing: density.spacing(.xs)) {
                        if viewModel.isChanging {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isChanging ? "Changing…" : buttonTitle)
                            .commandlyFont(size: 12, weight: .semibold)
                    }
                    .frame(minWidth: 178)
                    .padding(.horizontal, density.spacing(.md))
                    .padding(.vertical, density.spacing(.sm))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isChanging || viewModel.isRefreshing)
                .accessibilityLabel(buttonTitle)
                .accessibilityHint("Changes the mute state of the default input device across macOS")
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .commandlyFont(size: 10, weight: .medium)
                    .foregroundStyle(
                        viewModel.errorMessage == nil
                            ? SemanticColors.color(for: .secondaryText)
                            : SemanticColors.color(for: .danger)
                    )
                    .accessibilityLabel(statusMessage)
            }
        }
        .padding(density.spacing(.xl))
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: viewModel.isMuted)
    }

    private func statusMessage(forMutedState isMuted: Bool, canChange: Bool) -> String {
        guard canChange else {
            return "The current state is visible, but this device’s mute control is read-only."
        }
        return isMuted
            ? "Apps using the default input device receive muted audio."
            : "Apps using the default input device can receive microphone audio."
    }
}
