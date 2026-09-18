import DesignSystem
import Infrastructure
import SwiftUI

struct HighlightModeView: View {
    @Bindable var viewModel: HighlightModeViewModel
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight Mode")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            Image(systemName: "cursorarrow.rays")
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: density.iconSize, height: density.iconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Highlight Mode")
                    .commandlyFont(size: 14, weight: .semibold)
                Text("Presentation and recording feedback")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.state.isEnabled {
                Label("Active", systemImage: "record.circle.fill")
                    .commandlyFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Highlight Mode active")
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
    }

    private var content: some View {
        VStack(spacing: density.spacing(.lg)) {
            ZStack {
                Circle()
                    .fill((viewModel.state.isEnabled ? Color.green : Color.secondary).opacity(0.12))
                    .frame(width: 116, height: 116)
                Circle()
                    .stroke(
                        (viewModel.state.isEnabled ? Color.green : Color.secondary).opacity(0.24),
                        lineWidth: 1
                    )
                    .frame(width: 116, height: 116)
                Image(systemName: viewModel.state.isEnabled ? "cursorarrow.rays" : "cursorarrow")
                    .commandlyFont(size: 42, weight: .medium)
                    .foregroundStyle(viewModel.state.isEnabled ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }

            VStack(spacing: density.spacing(.xs)) {
                Text(viewModel.state.isEnabled ? "Highlight Mode On" : "Highlight Mode Off")
                    .commandlyFont(size: 22, weight: .semibold)
                Text(
                    viewModel.state.isEnabled
                        ? "Clicks, keystrokes, shortcuts, and cursor orientation are visible using your Applications settings."
                        : "Turn it on when presenting, teaching, or recording your screen."
                )
                .commandlyFont(size: 12)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            }

            Button(action: viewModel.toggle) {
                HStack(spacing: density.spacing(.xs)) {
                    if viewModel.isChanging {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isChanging ? "Changing…" : viewModel.primaryActionTitle)
                        .commandlyFont(size: 12, weight: .semibold)
                }
                .frame(minWidth: 190)
                .padding(.horizontal, density.spacing(.md))
                .padding(.vertical, density.spacing(.sm))
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isChanging)
            .accessibilityHint("Starts or stops global visual input feedback")

            if let statusMessage = viewModel.statusMessage {
                VStack(spacing: density.spacing(.xs)) {
                    Text(statusMessage)
                        .commandlyFont(size: 10.5, weight: .medium)
                        .foregroundStyle(
                            viewModel.errorMessage == nil ? Color.secondary : Color.red
                        )
                        .multilineTextAlignment(.center)

                    if viewModel.errorMessage != nil {
                        Button("Open Permission Settings", action: viewModel.openPermissions)
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    if viewModel.state.isEnabled == false {
                        Text("macOS Accessibility access is requested only when you turn this on.")
                            .commandlyFont(size: 10.5, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    Text("Assign a global shortcut in Settings → Applications → Highlight Mode.")
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                }
                .multilineTextAlignment(.center)
            }
        }
        .padding(density.spacing(.xl))
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: viewModel.state)
    }
}
