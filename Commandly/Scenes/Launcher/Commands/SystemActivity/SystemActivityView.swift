import CommandKit
import DesignSystem
import SwiftUI

struct SystemActivityView: View {
    @Bindable var viewModel: SystemActivityViewModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)

            Group {
                switch viewModel.mode {
                case .resources:
                    resourcesSurface
                case .applications:
                    applicationsSurface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: viewModel.mode) { _, mode in
            isSearchFocused = mode == .applications
        }
        .alert(
            viewModel.pendingConfirmation?.title ?? "Confirm Action",
            isPresented: confirmationBinding,
            presenting: viewModel.pendingConfirmation
        ) { confirmation in
            Button("Cancel", role: .cancel) {
                viewModel.cancelConfirmation()
            }
            Button(
                confirmation.confirmButtonTitle,
                role: .destructive
            ) {
                viewModel.confirm(confirmation)
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingConfirmation != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelConfirmation()
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            if viewModel.mode == .applications {
                applicationSearchField
            } else {
                HStack(spacing: density.spacing(.xs)) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .commandlyFont(size: 14, weight: .semibold)
                        .foregroundStyle(BrandPalette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("System Activity")
                            .commandlyFont(size: 14, weight: .semibold)
                        Text("A private, on-device snapshot of this Mac")
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: density.spacing(.sm))

            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing system activity")
            }

            CommandlyOptionMenu(
                items: SystemActivityMode.allCases.map {
                    CommandlyOptionItem(id: $0.rawValue, title: $0.title)
                },
                selectionID: viewModel.mode.rawValue,
                placeholderTitle: "View",
                allowsSearch: false,
                accessibilityLabelText: "System Activity view"
            ) { item in
                if let mode = SystemActivityMode(rawValue: item.id) {
                    viewModel.setMode(mode)
                }
            }
            .zIndex(30)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .background(LauncherPalette.chrome)
        .zIndex(20)
    }

    private var applicationSearchField: some View {
        HStack(spacing: density.spacing(.xs)) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 13, weight: .medium)
                .foregroundStyle(.tertiary)

            TextField("Filter running applications…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .commandlyFont(size: 14, weight: .medium)
                .focused($isSearchFocused)
                .accessibilityIdentifier("system-activity-application-query")
                .onSubmit {
                    viewModel.activateSelectedApplication()
                }
                .onKeyPress(.upArrow) {
                    viewModel.moveSelection(offset: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    viewModel.moveSelection(offset: 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    if viewModel.handleEscape() == false {
                        viewModel.goBack()
                    }
                    return .handled
                }
        }
        .padding(.horizontal, density.spacing(.sm))
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(Color.primary.opacity(isSearchFocused ? 0.09 : 0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(Color.primary.opacity(isSearchFocused ? 0.18 : 0), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var resourcesSurface: some View {
        if let resources = viewModel.resources {
            ScrollView {
                VStack(alignment: .leading, spacing: density.spacing(.md)) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                            Text("Machine Overview")
                                .commandlyFont(size: 18, weight: .semibold)
                            Text("Aggregate values only; Commandly does not inspect process contents.")
                                .commandlyFont(size: 11, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Sampled \(resources.sampledAt.formatted(date: .omitted, time: .standard))")
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.tertiary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 185), spacing: density.spacing(.sm))],
                        alignment: .leading,
                        spacing: density.spacing(.sm)
                    ) {
                        SystemResourceCard(
                            title: "CPU",
                            value: Self.percent(resources.cpuUsage),
                            subtitle: "Aggregate processor load",
                            systemImage: "cpu",
                            tint: BrandPalette.accent,
                            fraction: resources.cpuUsage
                        )
                        SystemResourceCard(
                            title: "Memory",
                            value: Self.usedAndTotalBytes(
                                used: resources.memoryUsedBytes,
                                total: resources.memoryTotalBytes
                            ),
                            subtitle: "Excludes free and reclaimable pages",
                            systemImage: "memorychip",
                            tint: .purple,
                            fraction: Self.fraction(
                                used: resources.memoryUsedBytes,
                                total: resources.memoryTotalBytes
                            )
                        )
                        SystemResourceCard(
                            title: "Storage",
                            value: "\(Self.bytes(resources.diskUsedBytes)) / \(Self.bytes(resources.diskTotalBytes))",
                            subtitle: "Used on the home volume",
                            systemImage: "internaldrive",
                            tint: .orange,
                            fraction: Self.fraction(
                                used: resources.diskUsedBytes,
                                total: resources.diskTotalBytes
                            )
                        )
                        SystemResourceCard(
                            title: "Uptime",
                            value: Self.uptime(resources.systemUptime),
                            subtitle: "Since the last system boot",
                            systemImage: "clock.arrow.circlepath",
                            tint: .cyan
                        )
                        SystemResourceCard(
                            title: "Thermal State",
                            value: resources.thermalState.title,
                            subtitle: Self.thermalDescription(resources.thermalState),
                            systemImage: "thermometer.medium",
                            tint: Self.thermalColor(resources.thermalState)
                        )
                        SystemResourceCard(
                            title: "GUI Applications",
                            value: "\(viewModel.applications.count)",
                            subtitle: "Regular applications currently running",
                            systemImage: "macwindow.on.rectangle",
                            tint: .green
                        )
                    }

                    HStack(spacing: density.spacing(.xs)) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                        Text("All metrics come from public macOS APIs and stay on this Mac.")
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, density.spacing(.xs))
                    .accessibilityElement(children: .combine)
                }
                .padding(density.spacing(.lg))
            }
            .background(LauncherPalette.detail)
        } else {
            LauncherApplicationEmptyState(
                systemImage: viewModel.isRefreshing
                    ? "arrow.trianglehead.2.clockwise.rotate.90"
                    : "gauge.with.dots.needle.67percent",
                title: viewModel.isRefreshing ? "Sampling this Mac" : "System activity unavailable",
                message: viewModel.isRefreshing
                    ? "Gathering aggregate resources and running applications."
                    : "Choose Refresh to try again."
            )
            .background(LauncherPalette.detail)
        }
    }

    private var applicationsSurface: some View {
        HStack(spacing: 0) {
            applicationSidebar
                .frame(width: 280)
                .background(LauncherPalette.sidebar)

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(width: 1)

            applicationDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LauncherPalette.detail)
        }
    }

    private var applicationSidebar: some View {
        Group {
            if viewModel.filteredApplications.isEmpty {
                LauncherApplicationEmptyState(
                    systemImage: "macwindow",
                    title: viewModel.applications.isEmpty
                        ? "No running applications"
                        : "No matching applications",
                    message: viewModel.applications.isEmpty
                        ? "Regular GUI applications will appear here."
                        : "Try a name, bundle identifier, or process ID."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.filteredApplications) { application in
                            applicationRow(application)
                        }
                    }
                    .padding(.vertical, density.spacing(.xs))
                }
            }
        }
    }

    private func applicationRow(_ application: SystemApplicationSnapshot) -> some View {
        LauncherApplicationRow(
            isSelected: application.processIdentifier
                == viewModel.selectedApplication?.processIdentifier,
            onSelect: {
                viewModel.select(processIdentifier: application.processIdentifier)
            },
            onOpen: {
                viewModel.select(processIdentifier: application.processIdentifier)
                viewModel.activateSelectedApplication()
            },
            onContextAction: {
                viewModel.select(processIdentifier: application.processIdentifier)
                viewModel.showsActionsMenu = true
            },
            onHoverChange: { hovering in
                if hovering {
                    viewModel.select(processIdentifier: application.processIdentifier)
                }
            }
        ) {
            HStack(spacing: density.spacing(.sm)) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                    Image(systemName: "app.fill")
                        .commandlyFont(size: 13, weight: .medium)
                        .foregroundStyle(application.isFrontmost ? BrandPalette.accent : .secondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.localizedName)
                        .commandlyFont(size: 12, weight: .semibold)
                        .lineLimit(1)
                    HStack(spacing: density.spacing(.xxs)) {
                        Text("PID \(application.processIdentifier)")
                        if application.isFrontmost {
                            Text("• Frontmost")
                                .foregroundStyle(BrandPalette.accent)
                        } else if application.isHidden {
                            Text("• Hidden")
                        }
                    }
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(application.localizedName)
            .accessibilityValue(Self.accessibilityStatus(for: application))
        } accessory: {
            EmptyView()
        }
    }

    @ViewBuilder
    private var applicationDetail: some View {
        if let application = viewModel.selectedApplication {
            ScrollView {
                VStack(alignment: .leading, spacing: density.spacing(.md)) {
                    HStack(spacing: density.spacing(.md)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                                .fill(BrandPalette.accent.opacity(0.12))
                            Image(systemName: "app.fill")
                                .commandlyFont(size: 28, weight: .medium)
                                .foregroundStyle(BrandPalette.accent)
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                            Text(application.localizedName)
                                .commandlyFont(size: 20, weight: .semibold)
                                .textSelection(.enabled)
                            Text(application.bundleIdentifier ?? "No bundle identifier")
                                .commandlyFont(size: 11, weight: .medium, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                        LauncherApplicationMetadataRow(
                            label: "Process",
                            value: String(application.processIdentifier),
                            labelWidth: 74
                        )
                        LauncherApplicationMetadataRow(
                            label: "Visibility",
                            value: application.isHidden ? "Hidden" : "Visible",
                            labelWidth: 74
                        )
                        LauncherApplicationMetadataRow(
                            label: "Position",
                            value: application.isFrontmost ? "Frontmost" : "Background",
                            labelWidth: 74
                        )
                    }
                    .padding(density.spacing(.md))
                    .background(Color.primary.opacity(0.045))
                    .clipShape(
                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                            .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                    }

                    if let reason = viewModel.terminationProtectionReason(for: application) {
                        Label(reason, systemImage: "shield.lefthalf.filled")
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                            .padding(density.spacing(.sm))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BrandPalette.accent.opacity(0.08))
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: CornerRadius.md.rawValue,
                                    style: .continuous
                                )
                            )
                    }

                    HStack(spacing: density.spacing(.sm)) {
                        Button("Switch to Application") {
                            viewModel.activateSelectedApplication()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isPerformingAction)

                        Button("Quit") {
                            viewModel.quitSelectedApplication()
                        }
                        .disabled(viewModel.canTerminateSelectedApplication == false)

                        Button("Force Quit…", role: .destructive) {
                            viewModel.requestForceQuitSelectedApplication()
                        }
                        .disabled(viewModel.canTerminateSelectedApplication == false)
                    }

                    Divider().opacity(0.35)

                    VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                        Text("Close Other Applications")
                            .commandlyFont(size: 12, weight: .semibold)
                        Text("Gracefully asks every unprotected GUI application to quit and reports any failures.")
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                        Button("Quit All Other Applications…", role: .destructive) {
                            viewModel.requestQuitAllApplications()
                        }
                        .disabled(
                            viewModel.quitAllCandidates.isEmpty || viewModel.isPerformingAction
                        )
                    }

                    if viewModel.isPerformingAction {
                        HStack(spacing: density.spacing(.xs)) {
                            ProgressView().controlSize(.small)
                            Text("Completing application action…")
                                .commandlyFont(size: 10, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(density.spacing(.lg))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            LauncherApplicationEmptyState(
                systemImage: "macwindow.on.rectangle",
                title: "Select an application",
                message: "Switch to it, request a graceful quit, or explicitly confirm a force quit."
            )
        }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private static func usedAndTotalBytes(used: UInt64, total: UInt64) -> String {
        "\(bytes(used)) / \(bytes(total))"
    }

    private static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func fraction(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    private static func uptime(_ interval: TimeInterval) -> String {
        let totalHours = Int(interval / 3_600)
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        let minutes = max(Int(interval / 60) % 60, 0)
        return "\(hours)h \(minutes)m"
    }

    private static func thermalDescription(_ state: SystemThermalState) -> String {
        switch state {
        case .nominal: return "No thermal pressure"
        case .fair: return "Light thermal pressure"
        case .serious: return "Performance may be reduced"
        case .critical: return "Significant thermal pressure"
        case .unknown: return "macOS did not report a state"
        }
    }

    private static func thermalColor(_ state: SystemThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    private static func accessibilityStatus(for application: SystemApplicationSnapshot) -> String {
        var values = ["Process \(application.processIdentifier)"]
        if application.isFrontmost { values.append("frontmost") }
        if application.isHidden { values.append("hidden") }
        return values.joined(separator: ", ")
    }
}

private struct SystemResourceCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var fraction: Double?

    @Environment(\.commandlyLayoutDensity) private var density

    init(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        fraction: Double? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.fraction = fraction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            HStack {
                Image(systemName: systemImage)
                    .commandlyFont(size: 15, weight: .semibold)
                    .foregroundStyle(tint)
                Spacer()
                Text(title.uppercased())
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
            }

            Text(value)
                .commandlyFont(size: 19, weight: .semibold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }

            Text(subtitle)
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(density.spacing(.md))
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value). \(subtitle)")
    }
}
