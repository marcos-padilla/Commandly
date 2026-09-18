import CommandKit
import DesignSystem
import SwiftUI

struct PortManagerView: View {
    @Bindable var viewModel: PortManagerViewModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(LauncherPalette.separator).frame(height: 1)
            content
        }
        .task { viewModel.start(); isSearchFocused = true }
        .onDisappear { viewModel.stop() }
        .alert("Stop \(viewModel.pendingTermination?.processName ?? "process")?", isPresented: confirmationBinding) {
            Button("Cancel", role: .cancel) { viewModel.perform(PortManagerActionID.cancel) }
            Button("Stop Process", role: .destructive) { viewModel.perform(PortManagerActionID.confirm) }
        } message: {
            if let listener = viewModel.pendingTermination {
                Text("This sends a termination request to \(listener.processName) (PID \(listener.processIdentifier)), which owns \(listener.transport.title) port \(listener.port). Unsaved work may be lost.")
            }
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { viewModel.pendingTermination != nil }, set: { if $0 == false { viewModel.perform(PortManagerActionID.cancel) } })
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(BrandPalette.accent)
            TextField("Filter ports or processes…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel("Filter listening ports")
                .onSubmit { viewModel.perform(PortManagerActionID.terminate) }
                .onKeyPress(.upArrow) { viewModel.moveSelection(offset: -1); return .handled }
                .onKeyPress(.downArrow) { viewModel.moveSelection(offset: 1); return .handled }
                .onKeyPress(.escape) { viewModel.goBack(); return .handled }
            Spacer()
            if viewModel.isRefreshing { ProgressView().controlSize(.small).accessibilityLabel("Refreshing ports") }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
    }

    @ViewBuilder private var content: some View {
        if viewModel.filteredListeners.isEmpty {
            LauncherApplicationEmptyState(
                systemImage: viewModel.isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "network",
                title: viewModel.isRefreshing ? "Inspecting local listeners" : "No matching listening ports",
                message: "Only local TCP and UDP listeners visible to this Mac are shown."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredListeners) { listener in
                        LauncherApplicationRow(
                            isSelected: listener.id == viewModel.selectedListener?.id,
                            onSelect: { viewModel.select(listener) },
                            onOpen: { viewModel.select(listener); viewModel.perform(PortManagerActionID.terminate) },
                            onContextAction: { viewModel.select(listener); viewModel.showsActionsMenu = true },
                            onHoverChange: { if $0 { viewModel.select(listener) } }
                        ) {
                            HStack(spacing: density.spacing(.sm)) {
                                Text(listener.transport.title)
                                    .commandlyFont(size: 10, weight: .bold)
                                    .foregroundStyle(BrandPalette.accent)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Port \(listener.port)  •  \(listener.processName)")
                                        .commandlyFont(size: 13, weight: .semibold)
                                    Text("\(listener.address.isEmpty ? "All interfaces" : listener.address)  •  PID \(listener.processIdentifier)")
                                        .commandlyFont(size: 10, weight: .medium)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        } accessory: {
                            EmptyView()
                        }
                        .accessibilityLabel("\(listener.transport.title) port \(listener.port), \(listener.processName), process \(listener.processIdentifier)")
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }
        }
        if let statusMessage = viewModel.statusMessage {
            Text(statusMessage)
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(density.spacing(.sm))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
