import DesignSystem
import Foundation
import Infrastructure
import SwiftUI

struct DisplayResolutionView: View {
    @Bindable var model: DisplayResolutionCoordinator
    @FocusState private var modeListIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "display").foregroundStyle(BrandPalette.accentSoft)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Display Resolution").commandlyFont(size: 17, weight: .semibold).accessibilityAddTraits(.isHeader)
                    Text("Try a mode, then keep it or return safely.").commandlyFont(size: 11).foregroundStyle(.secondary)
                }
                Spacer()
                if model.hasPendingChange == false {
                    Button("Refresh") { model.refresh() }.disabled(model.phase == .loading)
                }
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.hasPendingChange { previewContent }
                    else { chooser }
                    if let status = model.statusMessage {
                        Text(status).commandlyFont(size: 12).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .accessibilityIdentifier("display-resolution-status")
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            controls.padding(16)
        }
        .commandlyFont(size: 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display resolution chooser")
    }

    @ViewBuilder private var chooser: some View {
        if model.phase == .loading {
            ProgressView("Reading connected displays…")
        } else if let catalog = model.catalog, catalog.displays.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text("Display").commandlyFont(size: 12, weight: .semibold)
                Picker("Display", selection: Binding(get: { model.selectedDisplayID }, set: { if let value = $0 { model.selectDisplay(value) } })) {
                    ForEach(catalog.displays) { display in Text(display.name).tag(Optional(display.id)) }
                }.labelsHidden().accessibilityLabel("Connected display")
                if let display = model.selectedDisplay {
                    if let reason = display.unavailableReason {
                        Text(reason).commandlyFont(size: 12).foregroundStyle(.secondary)
                    }
                    Text("Resolution").commandlyFont(size: 12, weight: .semibold)
                    LazyVStack(spacing: 0) {
                        ForEach(display.modes) { mode in modeRow(mode, current: mode.id == display.currentModeID) }
                    }
                    .focusable().focused($modeListIsFocused)
                    .onKeyPress(.upArrow) { model.moveModeSelection(offset: -1); return .handled }
                    .onKeyPress(.downArrow) { model.moveModeSelection(offset: 1); return .handled }
                    .onKeyPress(.return) {
                        guard model.canApply else { return .handled }
                        model.apply(); return .handled
                    }
                    .accessibilityLabel("Available resolution modes. Use the arrow keys to select a mode.")
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    if display.modesAreTruncated {
                        Text("This display reports more modes than the bounded list can show. Displays Settings may offer additional choices.")
                            .commandlyFont(size: 11).foregroundStyle(.secondary)
                    }
                }
                Text("Apply starts a 15-second preview. Keep uses this login session only; permanent preferences are never changed. Modes below 640 × 480 stay listed but cannot be previewed here.")
                    .commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("No available display modes").commandlyFont(size: 16, weight: .semibold)
            Text("Refresh the connected displays, or open System Settings and choose Displays.")
                .commandlyFont(size: 12).foregroundStyle(.secondary)
        }
    }

    private func modeRow(_ mode: DisplayResolutionMode, current: Bool) -> some View {
        Button { model.selectMode(mode.id); modeListIsFocused = true } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: model.selectedModeID == mode.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(model.selectedModeID == mode.id ? BrandPalette.accentSoft : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Self.title(mode)).commandlyFont(size: 13, weight: .medium)
                        if current { Text("Current").commandlyFont(size: 10).foregroundStyle(.secondary) }
                    }
                    Text(Self.detail(mode)).commandlyFont(size: 10).foregroundStyle(.secondary)
                    if mode.canPreview == false {
                        Text("Too small for the confirmation window").commandlyFont(size: 10).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.title(mode)), \(Self.detail(mode))\(current ? ", current mode" : "")")
        .accessibilityValue(model.selectedModeID == mode.id ? "Selected" : "Not selected")
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.phase == .preview {
                Text("Keep this resolution?").commandlyFont(size: 22, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("Reverting automatically in \(model.remainingSeconds) seconds")
                    .commandlyFont(size: 16, weight: .medium).monospacedDigit()
                    .accessibilityIdentifier("display-resolution-countdown")
            } else if model.phase == .recovery {
                Label("The original mode is not confirmed", systemImage: "exclamationmark.triangle")
                    .commandlyFont(size: 18, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(model.attemptedSessionKeep
                    ? "A session change may have been committed. Quitting cannot guarantee its removal; use Displays Settings to recover the desired mode."
                    : "The temporary override is limited to Commandly’s lifetime. macOS normally removes it when Commandly exits, but that fallback is not a guarantee of the exact mode used before this preview.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary)
            } else { ProgressView(model.phase == .keeping ? "Keeping resolution…" : model.phase == .reverting ? "Reverting resolution…" : "Applying resolution…") }
            if let preview = model.preview {
                Text(preview.displayName).commandlyFont(size: 14, weight: .semibold)
                Text("Original: \(Self.title(preview.original))").commandlyFont(size: 12)
                Text("Preview: \(Self.title(preview.proposed))").commandlyFont(size: 12)
                Text(Self.detail(preview.proposed)).commandlyFont(size: 11).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var controls: some View {
        if model.phase == .preview {
            HStack {
                Button("Revert", action: model.revert).buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Keep for This Session", action: model.keep).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(model.canKeep == false)
            }
        } else if model.phase == .recovery {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Retry Revert", action: model.revert).buttonStyle(.borderedProminent)
                    Button("Open System Settings", action: model.openSystemSettings).buttonStyle(.bordered)
                }
                Button(model.attemptedSessionKeep ? "Quit Without Confirmed Restoration" : "Quit and Use macOS Recovery", action: model.quitWithoutExactRestore)
                    .buttonStyle(.borderless).commandlyFont(size: 11)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else if model.hasPendingChange {
            HStack {
                Text("Keep the app open while macOS completes this operation.").commandlyFont(size: 11).foregroundStyle(.secondary)
                Spacer()
                if model.phase == .applying { Button("Cancel", action: model.revert).buttonStyle(.bordered) }
            }
        } else {
            HStack {
                Button("System Settings", action: model.openSystemSettings).buttonStyle(.borderless)
                Spacer()
                Button("Close", action: model.requestClose).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                Button("Apply Preview", action: model.apply).buttonStyle(.borderedProminent).disabled(model.canApply == false)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private static func title(_ mode: DisplayResolutionMode) -> String { "\(mode.logicalWidth) × \(mode.logicalHeight)" }
    private static func detail(_ mode: DisplayResolutionMode) -> String {
        let density = mode.isHighDensity ? "HiDPI · \(mode.pixelWidth) × \(mode.pixelHeight) pixels" : "\(mode.pixelWidth) × \(mode.pixelHeight) pixels"
        let refresh = mode.refreshRate.map { String(format: "%.2f Hz", $0) } ?? "Refresh rate not reported"
        return "\(density) · \(refresh)"
    }
}
