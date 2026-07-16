import DesignSystem
import SwiftUI

struct AISettingsPage: View {
    @Bindable var model: AISettingsModel
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case credential
        case endpoint
    }

    var body: some View {
        SettingsPageLayout(maxWidth: 760) {
            VStack(alignment: .leading, spacing: max(24, density.pageStackSpacing + 8)) {
                privacyNote
                connectionsSection
                setupSection
                feedback
            }
        }
        .task {
            await model.load()
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: density.spacing(.sm)) {
            settingsGlyph("lock.shield.fill", emphasized: true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Bring your own key")
                    .commandlyFont(size: 12.5, weight: .semibold)
                Text(
                    "Cloud API keys are stored in your macOS Keychain, never in Commandly preferences. "
                        + "Prompts and bounded Finder metadata/tool results go directly to the provider you select; "
                        + "file contents are sent only after approval. "
                        + "Inference usage and any charges stay with that provider account."
                )
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .accessibilityElement(children: .combine)
    }

    private var connectionsSection: some View {
        SettingsSection("Connected Providers") {
            if model.configuredConnections.isEmpty {
                HStack(spacing: density.spacing(.sm)) {
                    settingsGlyph("link.badge.plus")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No provider connected")
                            .commandlyFont(size: 12.5, weight: .medium)
                        Text("Validate a credential or local endpoint below to get started.")
                            .commandlyFont(size: 10.5)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, Spacing.xs.rawValue)
                .padding(.vertical, max(8, density.rowVerticalPadding))
            } else {
                ForEach(Array(model.configuredConnections.enumerated()), id: \.element.id) {
                    index, connection in
                    if index > 0 { SettingsDivider() }
                    connectionRow(connection)
                }
            }
        }
    }

    private func connectionRow(_ connection: StoredAIConnection) -> some View {
        let provider = model.providers.first { $0.id == connection.providerID }
        let isActive = model.preferences.activeProviderID == connection.providerID
        return HStack(spacing: density.spacing(.sm)) {
            settingsGlyph(
                provider?.systemImage ?? "brain",
                emphasized: isActive
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider?.title ?? connection.providerID)
                        .commandlyFont(size: 12.5, weight: .medium)
                    if isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .commandlyFont(size: 9, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(connection.modelDisplayName)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: density.spacing(.xs))

            if isActive == false {
                Button("Make Active") {
                    model.makeActive(connection.providerID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isBusy)
                .accessibilityLabel("Make \(provider?.title ?? connection.providerID) active")
            }

            Button("Disconnect", role: .destructive) {
                model.disconnect(connection.providerID)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isBusy)
            .accessibilityLabel("Disconnect \(provider?.title ?? connection.providerID)")
        }
        .padding(.horizontal, Spacing.xs.rawValue)
        .padding(.vertical, max(8, density.rowVerticalPadding))
    }

    private var setupSection: some View {
        SettingsSection("Add or Update a Provider") {
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                AIFormRow("Provider") {
                    Picker("Provider", selection: providerSelection) {
                        Text("Choose a provider…").tag("")
                        ForEach(model.providers) { provider in
                            Label(provider.title, systemImage: provider.systemImage)
                                .tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(model.isBusy)
                    .accessibilityLabel("AI provider")
                }

                if let provider = model.selectedProvider {
                    Divider()
                        .overlay(SettingsVisualStyle.separator)

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.title)
                                .commandlyFont(size: 12.5, weight: .semibold)
                            Text(provider.subtitle)
                                .commandlyFont(size: 10.5)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if provider.supportsToolRuntime == false {
                            Text("MODEL DISCOVERY ONLY")
                                .commandlyFont(size: 8.5, weight: .bold)
                                .foregroundStyle(.orange)
                        }
                    }

                    if provider.requiresCredential {
                        AIFormRow("API key") {
                            SecureField("Paste API key", text: $model.credentialInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 310)
                                .accessibilityLabel("API key")
                                .focused($focusedField, equals: .credential)
                                .onChange(of: model.credentialInput) { _, _ in
                                    model.credentialDraftDidChange()
                                }
                                .disabled(model.isBusy)
                                .privacySensitive()
                                .accessibilityHint(
                                    "The key stays in memory until validation and is stored in Keychain only after model selection."
                                )
                        }
                    }

                    if provider.allowsEndpointEditing {
                        AIFormRow("Local endpoint") {
                            TextField("http://localhost:11434", text: $model.endpointInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 310)
                                .accessibilityLabel("Local endpoint")
                                .focused($focusedField, equals: .endpoint)
                                .disabled(model.isBusy)
                                .accessibilityHint("Only loopback endpoints are accepted.")
                        }
                    }

                    HStack {
                        Spacer()
                        if model.phase == .validating {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Validating provider")
                        }
                        Button(model.preferences.connection(for: provider.id) == nil ? "Validate" : "Revalidate") {
                            focusedField = nil
                            model.validate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.canValidate == false)
                    }

                    if model.discoveredModels.isEmpty == false {
                        Divider()
                            .overlay(SettingsVisualStyle.separator)

                        AIFormRow("Available model") {
                            Picker("Available model", selection: modelSelection) {
                                ForEach(model.discoveredModels) { availableModel in
                                    Text(modelTitle(availableModel)).tag(availableModel.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 310)
                            .accessibilityHint("Models returned for the validated credential.")
                        }

                        HStack {
                            if let selected = model.selectedModel,
                               selected.supportsTools == false {
                                Label(
                                    "This model may not support Finder tools.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .commandlyFont(size: 10)
                                .foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Save & Use Model") {
                                model.saveSelection()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(model.canSave == false)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xs.rawValue)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = model.errorMessage {
            SettingsStatusBanner(
                message: error,
                tint: .red,
                systemImage: "exclamationmark.triangle.fill"
            )
            .accessibilityLabel("AI settings error: \(error)")
        } else if let status = model.statusMessage {
            SettingsStatusBanner(
                message: status,
                tint: .green,
                systemImage: "checkmark.circle.fill"
            )
        }
    }

    private var providerSelection: Binding<String> {
        Binding(
            get: { model.selectedProviderID ?? "" },
            set: { value in
                if value.isEmpty { model.resetDraft() } else { model.selectProvider(value) }
            }
        )
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { model.selectedModelID ?? "" },
            set: { model.selectedModelID = $0 }
        )
    }

    private func modelTitle(_ availableModel: AIModelOption) -> String {
        availableModel.supportsTools
            ? availableModel.displayName
            : "\(availableModel.displayName) — tools unverified"
    }
}

private struct AIFormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md.rawValue) {
            Text(title)
                .commandlyFont(size: 11.5, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            Spacer(minLength: Spacing.sm.rawValue)
            content()
        }
    }
}

#Preview("AI Settings") {
    AISettingsPage(model: AISettingsModel())
        .frame(width: 720, height: 680)
}
