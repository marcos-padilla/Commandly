import DesignSystem
import SwiftUI

struct FinderPathView: View {
    @Bindable var viewModel: FinderPathViewModel
    let copyImmediately: Bool
    @Environment(\.commandlyLayoutDensity) private var density
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CommandlyBackButton(action: viewModel.goBack)
                Text("Finder Path").commandlyFont(size: 14, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer()
            }.padding(density.spacing(.md))
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: density.spacing(.md)) {
                    Label("Copy the path you’re working with", systemImage: "folder")
                        .commandlyFont(size: 18, weight: .semibold).accessibilityAddTraits(.isHeader)
                    Text("Select one item in a Finder folder window to copy its path. With nothing selected, copy that window’s current folder. Select just one item when several are highlighted.")
                        .commandlyFont(size: 12).fixedSize(horizontal: false, vertical: true)
                    Text("Commandly reads Finder only for this action. macOS may ask for Automation access. File contents stay untouched; copying a path does not grant Commandly access to the file.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(viewModel.primaryTitle, action: viewModel.performPrimary)
                            .buttonStyle(.borderedProminent).disabled(!viewModel.canCopy).keyboardShortcut(.defaultAction)
                        if viewModel.isWorking {
                            ProgressView().controlSize(.small)
                            Button("Cancel") { viewModel.perform(FinderPathActionID.cancel) }
                        }
                    }
                    if viewModel.permissionDenied {
                        Button("Open System Settings", action: viewModel.openSettings).disabled(viewModel.isWorking)
                    }
                    if let label = viewModel.fixtureLabel {
                        Label(label, systemImage: "testtube.2").commandlyFont(size: 11).foregroundStyle(.orange)
                    }
                    Text("The path is copied as plain text, without shell escaping. Desktop-only selection and locations without a concrete file path are unavailable. Clipboard History may retain copied text if enabled.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(density.spacing(.lg)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(LauncherPalette.detail)
        .accessibilityElement(children: .contain).accessibilityLabel("Finder path copying")
        .task { viewModel.activate(copyImmediately: copyImmediately) }
        .onDisappear { viewModel.stop() }
    }
}
