import DesignSystem
import Infrastructure
import SwiftUI

struct NotionWorkspaceView: View {
    @Bindable var model: NotionWorkspaceViewModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyBackButton(action: model.back)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notion Workspace").commandlyFont(size: 14, weight: .semibold)
                    Text(model.title).commandlyFont(size: 11).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Connection…", action: model.showConnection).controlSize(.small)
            }.padding(12).background(LauncherPalette.chrome)
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                TextField("Search shared page and database titles", text: $model.query)
                    .textFieldStyle(.plain).commandlyFont(size: 14).focused($searchFocused)
                    .onSubmit(model.search).accessibilityLabel("Search Notion page titles")
                    .onKeyPress(.downArrow) { model.moveSelection(offset: 1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(offset: -1); return .handled }
                if model.busy { ProgressView().controlSize(.small); Button("Cancel", action: model.cancel).controlSize(.small) }
                else { Button("Search", action: model.search).controlSize(.small) }
            }.padding(14)
            Divider().opacity(0.5)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.errorMessage { Text(error).commandlyFont(size: 11).foregroundStyle(.orange).padding(10).frame(maxWidth: .infinity, alignment: .leading) }
            if model.cursor != nil, model.items.count < 1000 {
                Button("Load More", action: model.loadMore).disabled(model.busy).padding(8)
            }
        }.background(LauncherPalette.detail)
            .task { model.start(); searchFocused = true }
            .onDisappear(perform: model.stop)
            .sheet(isPresented: $model.showsConnection, onDismiss: { model.closeConnection(); searchFocused = true }) { connectionSheet }
            .accessibilityElement(children: .contain).accessibilityLabel("Notion workspace browser")
    }
    @ViewBuilder private var content: some View {
        if model.connection == nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Your shared workspace, within reach", systemImage: "doc.text.magnifyingglass").commandlyFont(size: 18, weight: .semibold)
                    Text("Connect an internal Notion integration to browse pages and databases you share with it. Search is by title; opening a page loads its readable blocks.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary)
                    Button("Connect Workspace…", action: model.showConnection).buttonStyle(.borderedProminent)
                    Text("Searches and page requests go directly to Notion. Nothing is sent to AI or saved as browsing history.").commandlyFont(size: 11).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        } else if model.items.isEmpty {
            Text(model.busy ? "Loading from Notion…" : model.route.isEmpty ? "Search by title, or submit an empty search to browse shared pages. If a page is missing, share it with your integration in Notion." : "No readable blocks were returned. Open the page in Notion to see its full presentation.")
                .commandlyFont(size: 12).foregroundStyle(.secondary).padding(24)
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.items) { item in
                            HStack(spacing: 9) {
                                Image(systemName: item.hasChildren ? "folder" : "text.alignleft").foregroundStyle(.secondary)
                                Text(item.title).commandlyFont(size: 12).lineLimit(2)
                                Spacer(minLength: 0)
                                if item.hasChildren { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.vertical, 4).tag(item.id).id(item.id)
                                .accessibilityLabel(item.title + (item.hasChildren ? ", browse contents" : ", text block"))
                                .onTapGesture(count: 2) { model.selectedID = item.id; model.browseSelection() }
                        }
                    }.listStyle(.sidebar).frame(minWidth: 200, idealWidth: 260, maxWidth: 310)
                        .onKeyPress(.return) { model.browseSelection(); return .handled }
                        .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
                Divider().opacity(0.5)
                ScrollView {
                    if let selected = model.selected {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(selected.title).commandlyFont(size: 16, weight: .semibold).textSelection(.enabled)
                            if !selected.text.isEmpty { Text(selected.text).commandlyFont(size: 12).textSelection(.enabled) }
                            if selected.hasChildren { Button("Browse Contents", action: model.browseSelection).disabled(model.busy) }
                            HStack { Button("Open in Notion", action: model.openSelection); Button("Copy Text", action: model.copySelection) }.controlSize(.small)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }
    private var connectionSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connect Notion").commandlyFont(size: 18, weight: .semibold)
                Spacer(); Button(model.busy ? "Cancel" : "Done", action: model.closeConnection).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Create an internal integration with Read content access. In Notion, add that connection to each page you want to browse. Paste its internal integration token below.").commandlyFont(size: 12)
                    Button("Open Notion Integrations", action: model.openSetup)
                    if let connection = model.connection {
                        Label(connection.name, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Remove Local Connection", action: model.disconnect).disabled(model.busy)
                    }
                    SecureField("Internal integration token", text: $model.token).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Notion internal integration token").disabled(model.busy).onSubmit(model.connect)
                    Button(model.connection == nil ? "Check & Connect" : "Check & Replace", action: model.connect)
                        .buttonStyle(.borderedProminent).disabled(model.token.isEmpty || model.busy)
                    Button("Reload Saved Connection", action: model.reloadConnection).disabled(model.busy)
                    if model.busy { ProgressView().controlSize(.small) }
                    if let error = model.errorMessage { Text(error).foregroundStyle(.orange).commandlyFont(size: 11) }
                    Text("The token is sent only to Notion and saved in Keychain after validation. Commandly uses read operations only. Removing it here does not revoke the integration in Notion.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(22).frame(width: 540).frame(maxHeight: 480)
    }
}
