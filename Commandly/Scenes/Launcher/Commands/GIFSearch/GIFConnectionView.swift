import DesignSystem
import Infrastructure
import SwiftUI

struct GIFConnectionView: View {
    @Bindable var model: GIFSearchViewModel
    @FocusState private var keyFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GIPHY Connection").commandlyFont(size: 18, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer(); Button("Done", action: model.closeConnection).disabled(model.isChangingConnection).keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            if let fixture = model.fixtureLabel {
                Label(fixture, systemImage: "testtube.2")
                    .commandlyFont(size: 11).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Use your own GIPHY API key. Commandly stores it in Keychain and sends it only to GIPHY's API when you explicitly search or load Trending.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack { providerLinks }
                VStack(alignment: .leading, spacing: 8) { providerLinks }
            }.controlSize(.small)
            Text("Create an API key for this macOS GIF integration in your own GIPHY account. Beta keys allow 100 API calls per hour; production access and pricing are managed by GIPHY. Commandly does not create an account or accept terms for you.")
                .commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField(model.connection?.isConfigured == true ? "Replacement API key" : "GIPHY API key", text: $model.apiKeyInput)
                .textFieldStyle(.roundedBorder).focused($keyFocused).accessibilityLabel("GIPHY API key")
                .onSubmit { if !model.apiKeyInput.isEmpty { model.saveKey() } }
                .disabled(model.isChangingConnection || model.isLoading)
            HStack {
                if model.isChangingConnection || model.isLoading { ProgressView().controlSize(.small) }
                Text(connectionStatus).commandlyFont(size: 11).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Refresh", action: model.refreshConnection).disabled(model.isChangingConnection || model.isLoading)
                Button("Remove Saved Key", action: model.disconnect).disabled(model.isChangingConnection || model.isLoading)
                Button("Save Key", action: model.saveKey).buttonStyle(.borderedProminent).disabled(model.apiKeyInput.isEmpty || model.isChangingConnection || model.isLoading)
            }.controlSize(.small)
            if let error = model.errorMessage { Text(error).commandlyFont(size: 11).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let status = model.statusMessage { Text(status).commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("Search phrases and media requests go directly to GIPHY, which can receive your IP address. Commandly adds no user IDs or analytics pings, and keeps no search history, cookies, or GIF cache. Changing or removing a key clears results and preview buffers.")
                .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Image("GIPHYAttribution").resizable().scaledToFit().frame(width: 200, height: 28).accessibilityLabel("Powered by GIPHY")
            }.padding(22)
            }
        }.frame(width: 580, height: 480)
            .onAppear { DispatchQueue.main.async { keyFocused = true } }
            .accessibilityElement(children: .contain).accessibilityLabel("GIPHY connection setup")
    }

    @ViewBuilder private var providerLinks: some View {
        Button("Open GIPHY Developer Dashboard", action: model.openProviderSetup)
        Button("API Terms", action: model.openProviderTerms)
    }

    private var connectionStatus: String {
        if model.fixtureLabel != nil {
            return model.connection?.isConfigured == true
                ? "Generated connection active. No API key is stored."
                : "Generated connection inactive. No API key is stored."
        }
        return model.connection?.isConfigured == true
            ? "A key is saved. Its value is never shown here."
            : "No active key loaded."
    }
}
