import DesignSystem
import SwiftUI

/// Quick Toggles tab: one card per everyday macOS switch.
struct QuickTogglesPanelSection: View {
    @Bindable var model: QuickTogglesModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            ForEach(model.presentations) { presentation in
                row(presentation)
            }

            if let message = model.errorMessage {
                Text(message)
                    .commandlyFont(size: 10)
                    .foregroundStyle(SemanticColors.color(for: .danger))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            if model.hiddenToggleList.isEmpty == false {
                hiddenFooter
            }
        }
        .onAppear { model.addObserver() }
        .onDisappear { model.removeObserver() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick toggles")
    }

    // MARK: - Rows

    private func row(_ presentation: QuickTogglePresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Spacing.sm.rawValue) {
                Image(systemName: presentation.toggle.symbolName)
                    .commandlyFont(size: 16, weight: .medium)
                    .foregroundStyle(iconTint(presentation))
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .commandlyFont(size: 13, weight: .semibold)
                        .foregroundStyle(presentation.isEnabled ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.caption)
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.xs.rawValue)

                trailing(presentation)
            }

            if model.confirming == presentation.toggle {
                confirmationRow(presentation)
            }
        }
        .statusPanelCard()
        .contentShape(RoundedRectangle(cornerRadius: StatusPanelChrome.cardCornerRadius, style: .continuous))
        .onTapGesture {
            guard presentation.isEnabled, presentation.control == .action else { return }
            model.activate(presentation.toggle)
        }
        .contextMenu {
            Button("Hide \(presentation.title)") {
                model.hide(presentation.toggle)
            }
            if presentation.toggle.settingsPane != nil {
                Button("Open in System Settings") {
                    model.openSettings(for: presentation.toggle)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.title)
        .accessibilityHint(presentation.caption)
    }

    @ViewBuilder
    private func trailing(_ presentation: QuickTogglePresentation) -> some View {
        if presentation.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Working")
        } else {
            switch presentation.control {
            case .toggle(let isOn):
                Toggle("", isOn: toggleBinding(presentation, isOn: isOn))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(presentation.title)

            case .action:
                Image(systemName: "chevron.right")
                    .commandlyFont(size: 11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

            case .unavailable:
                if presentation.toggle.settingsPane != nil {
                    Button {
                        model.openSettings(for: presentation.toggle)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .commandlyFont(size: 12)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open the System Settings page that can change this")
                    .accessibilityLabel("Open System Settings for \(presentation.title)")
                } else {
                    Image(systemName: "minus")
                        .commandlyFont(size: 11, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func toggleBinding(
        _ presentation: QuickTogglePresentation,
        isOn: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { isOn },
            set: { _ in model.activate(presentation.toggle) }
        )
    }

    private func iconTint(_ presentation: QuickTogglePresentation) -> Color {
        guard presentation.control != .unavailable else { return .secondary }
        switch presentation.toggle {
        case .emptyTrash: return CommandlyTint.red.color
        case .lockScreen: return CommandlyTint.blue.color
        default: return Color.accentColor
        }
    }

    /// Emptying the Trash cannot be undone, so the row asks before it does it.
    private func confirmationRow(_ presentation: QuickTogglePresentation) -> some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("This permanently removes everything in the Trash.")
                .commandlyFont(size: 10)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.xs.rawValue)

            Button("Cancel") { model.cancelConfirmation() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Empty") { model.confirm(presentation.toggle) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.top, 2)
    }

    // MARK: - Hidden rows

    private var hiddenFooter: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("Hidden toggles")
                .commandlyFont(size: 11, weight: .medium)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs.rawValue)
            Menu {
                ForEach(model.hiddenToggleList) { toggle in
                    Button("Show \(model.title(for: toggle))") {
                        model.show(toggle)
                    }
                }
                Divider()
                Button("Show All") { model.showAllToggles() }
            } label: {
                Text("\(model.hiddenToggleList.count) hidden")
                    .commandlyFont(size: 10.5)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }
}
