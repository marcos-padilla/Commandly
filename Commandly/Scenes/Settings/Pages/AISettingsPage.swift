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
        ScrollView {
            GlassEffectContainer(spacing: density.pageStackSpacing) {
                VStack(alignment: .leading, spacing: density.pageStackSpacing) {
                    SettingsPageHeader(
                        title: "AI",
                        subtitle: "Connect your own provider account and choose the model Commandly uses."
                    )

                    privacyCard
                    connectionsCard
                    setupCard
                    feedback
                }
            }
            .padding(.horizontal, Spacing.md.rawValue)
            .padding(.vertical, Spacing.md.rawValue)
        }
        .task {
            await model.load()
        }
    }

    private var privacyCard: some View {
        SettingsCard {
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
            .padding(6)
            .accessibilityElement(children: .combine)
        }
    }

    private var connectionsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Connected providers")

                if model.configuredConnections.isEmpty {
                    HStack(spacing: density.spacing(.sm)) {
                        settingsGlyph("link.badge.plus")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No provider connected")
                                .commandlyFont(size: 12.5, weight: .medium)
                            Text("Validate a credential or local endpoint below to get started.")
                                .commandlyFont(size: 10.5)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, density.rowVerticalPadding)
                } else {
                    ForEach(Array(model.configuredConnections.enumerated()), id: \.element.id) {
                        index, connection in
                        if index > 0 { SettingsDivider() }
                        connectionRow(connection)
                    }
                }
            }
        }
    }

    private func connectionRow(_ connection: StoredAIConnection) -> some View {
        let provider = model.providers.first { $0.id == connection.providerID }
        let isActive = model.preferences.activeProviderID == connection.providerID
        return HStack(spacing: density.spacing(.sm)) {
            settingsGlyph(provider?.systemImage ?? "brain", emphasized: isActive)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider?.title ?? connection.providerID)
                        .commandlyFont(size: 12.5, weight: .medium)
                    if isActive {
                        Text("ACTIVE")
                            .commandlyFont(size: 8.5, weight: .bold)
                            .foregroundStyle(BrandPalette.accentSoft)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(BrandPalette.accent.opacity(0.14))
                            )
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
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(model.isBusy)
            }

            Button("Disconnect", role: .destructive) {
                model.disconnect(connection.providerID)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(model.isBusy)
            .accessibilityLabel("Disconnect \(provider?.title ?? connection.providerID)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, max(5, density.rowVerticalPadding - 1))
    }

    private var setupCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Add or update a provider")

                LabeledContent("Provider") {
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
                    Divider().overlay(SettingsPalette.border)

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
                        LabeledContent("API key") {
                            SecureField("Paste API key", text: $model.credentialInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 310)
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
                        LabeledContent("Local endpoint") {
                            TextField("http://localhost:11434", text: $model.endpointInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 310)
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
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                        .disabled(model.canValidate == false)
                    }

                    if model.discoveredModels.isEmpty == false {
                        Divider().overlay(SettingsPalette.border)

                        LabeledContent("Available model") {
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
                                Label("This model may not support Finder tools.", systemImage: "exclamationmark.triangle")
                                    .commandlyFont(size: 10)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Save & Use Model") {
                                model.saveSelection()
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.small)
                            .disabled(model.canSave == false)
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("AI settings error: \(error)")
        } else if let status = model.statusMessage {
            Label(status, systemImage: "checkmark.circle.fill")
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private func sectionLabel(_ value: String) -> some View {
        Text(value.uppercased())
            .commandlyFont(size: 9, weight: .semibold)
            .foregroundStyle(.tertiary)
            .tracking(0.7)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("AI Settings") {
    AISettingsPage(model: AISettingsModel())
        .frame(width: 720, height: 680)
}
