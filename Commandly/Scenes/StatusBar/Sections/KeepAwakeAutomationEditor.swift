import AppKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// Chooses the conditions that start a Keep Awake session on their own.
struct KeepAwakeAutomationEditor: View {
    @Bindable var coordinator: KeepAwakeCoordinator
    @State private var isChoosingApplication = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            HStack(alignment: .top, spacing: 6) {
                conditionTile(
                    .externalDisplay,
                    isOn: coordinator.settings.startsWithExternalDisplay
                ) {
                    coordinator.settings.startsWithExternalDisplay.toggle()
                }
                conditionTile(
                    .connectedToPower,
                    isOn: coordinator.settings.startsWhenConnectedToPower
                ) {
                    coordinator.settings.startsWhenConnectedToPower.toggle()
                }
                conditionTile(
                    .runningApplications,
                    isOn: coordinator.settings.startsWithRunningApplications
                ) {
                    coordinator.settings.startsWithRunningApplications.toggle()
                }
            }

            if coordinator.settings.startsWithRunningApplications {
                applicationList
            }
        }
        .fileImporter(
            isPresented: $isChoosingApplication,
            allowedContentTypes: [.application],
            allowsMultipleSelection: true
        ) { result in
            handleApplicationChoice(result)
        }
    }

    private func conditionTile(
        _ condition: KeepAwakeAutomationCondition,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: condition.symbolName)
                        .commandlyFont(size: 14, weight: .semibold)
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    Spacer(minLength: 4)
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .commandlyFont(size: 11, weight: .semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(condition.title)
                    .commandlyFont(size: 10, weight: .medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.11) : LauncherPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isOn ? Color.accentColor.opacity(0.32) : LauncherPalette.separator
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(condition.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Apps that keep the Mac awake")
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)

            if coordinator.settings.runningApplicationBundleIdentifiers.isEmpty {
                Text("No apps chosen yet, so this rule never matches.")
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(coordinator.settings.runningApplicationBundleIdentifiers, id: \.self) { identifier in
                    applicationRow(identifier)
                }
            }

            Button("Add App…") {
                isChoosingApplication = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LauncherPalette.hover)
        )
    }

    private func applicationRow(_ identifier: String) -> some View {
        HStack(spacing: 6) {
            ApplicationLauncherIcon(bundleIdentifier: identifier, size: 14)
            Text(displayName(for: identifier))
                .commandlyFont(size: 10.5)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                coordinator.setRunningApplicationBundleIdentifiers(
                    coordinator.settings.runningApplicationBundleIdentifiers
                        .filter { $0 != identifier }
                )
            } label: {
                Image(systemName: "minus.circle")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(displayName(for: identifier))")
        }
    }

    private func displayName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return bundleIdentifier
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func handleApplicationChoice(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let identifiers = urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        guard identifiers.isEmpty == false else { return }
        coordinator.setRunningApplicationBundleIdentifiers(
            coordinator.settings.runningApplicationBundleIdentifiers + identifiers
        )
    }
}
