import DesignSystem
import Foundation
import SwiftUI

struct TimersView: View {
    private enum HeaderFocus: Hashable {
        case search
        case name
    }

    @Bindable var viewModel: TimersViewModel
    @FocusState private var headerFocus: HeaderFocus?
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 282)
                    .background(LauncherPalette.sidebar)

                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(width: 1)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LauncherPalette.detail)
            }
        }
        .onAppear {
            headerFocus = viewModel.isCreating ? .name : .search
        }
        .onChange(of: viewModel.isCreating) { _, isCreating in
            headerFocus = isCreating ? .name : .search
        }
        .accessibilityLabel("Timers and Focus")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)

            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: viewModel.isCreating ? "timer" : "magnifyingglass")
                    .symbolVariant(.none)
                    .commandlyFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: density.iconSize, height: density.iconSize)
                    .accessibilityHidden(true)

                headerTextField
            }
            .padding(.vertical, density.searchVerticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                headerFocus = viewModel.isCreating ? .name : .search
            }
            .layoutPriority(1)

            if viewModel.isCreating {
                if viewModel.allTimers.isEmpty == false {
                    Button("Cancel") {
                        viewModel.cancelCreating()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel new timer")
                }
            } else {
                CommandlyOptionMenu(
                    items: TimerFilter.allCases.map {
                        CommandlyOptionItem(id: $0.rawValue, title: $0.title)
                    },
                    selectionID: viewModel.filter.rawValue,
                    allowsSearch: false,
                    accessibilityLabelText: "Filter timers"
                ) { item in
                    if let filter = TimerFilter(rawValue: item.id) {
                        viewModel.filter = filter
                    }
                }

                Button {
                    viewModel.beginCreating()
                } label: {
                    Image(systemName: "plus")
                        .commandlyFont(size: 12, weight: .semibold)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("New timer")
                .help("New Timer (Command-N)")
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.top, density.spacing(.xs))
        .padding(.bottom, density.spacing(.xxs))
        .zIndex(20)
    }

    @ViewBuilder
    private var headerTextField: some View {
        if viewModel.isCreating {
            TextField("Name this timer…", text: $viewModel.draftName)
                .textFieldStyle(.plain)
                .commandlyFont(size: 16, weight: .medium)
                .focused($headerFocus, equals: .name)
                .accessibilityLabel("Timer name")
                .accessibilityIdentifier("timer-name")
                .onSubmit(viewModel.performPrimary)
                .onKeyPress(.escape) {
                    handleEscape()
                    return .handled
                }
        } else {
            TextField("Search timers…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .commandlyFont(size: 16, weight: .medium)
                .focused($headerFocus, equals: .search)
                .accessibilityLabel("Search timers")
                .accessibilityIdentifier("timers-query")
                .onSubmit(viewModel.performPrimary)
                .onKeyPress(.upArrow) {
                    viewModel.moveSelection(offset: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    viewModel.moveSelection(offset: 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    handleEscape()
                    return .handled
                }
        }
    }

    private var sidebar: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                    if viewModel.allTimers.isEmpty {
                        LauncherApplicationEmptyState(
                            systemImage: "timer",
                            title: "No timers yet",
                            message: "Start a Focus timer or create your own countdown."
                        )
                        .frame(minHeight: 260)
                    } else if viewModel.filteredTimers.isEmpty {
                        LauncherApplicationEmptyState(
                            systemImage: "line.3.horizontal.decrease.circle",
                            title: "No matching timers",
                            message: "Change the search or filter to see more timers."
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(viewModel.filteredTimers) { timer in
                            timerRow(timer)
                                .id(timer.id)
                        }
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func timerRow(_ timer: CountdownTimer) -> some View {
        LauncherApplicationRow(
            isSelected: timer.id == viewModel.selectedTimer?.id,
            onSelect: { viewModel.select(timer.id) },
            onOpen: {
                viewModel.select(timer.id)
                viewModel.performPrimary()
            },
            onContextAction: {
                viewModel.select(timer.id)
                viewModel.showsActionsMenu = true
            },
            onHoverChange: { hovering in
                if hovering {
                    viewModel.select(timer.id)
                }
            }
        ) {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: phaseSystemImage(timer.phase))
                    .commandlyFont(size: 12, weight: .semibold)
                    .foregroundStyle(phaseColor(timer.phase))
                    .frame(width: 22, height: 22)
                    .background(phaseColor(timer.phase).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))

                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.name)
                        .commandlyFont(size: 12, weight: .semibold)
                        .lineLimit(1)
                    Text(viewModel.phaseTitle(for: timer.phase))
                        .commandlyFont(size: 9, weight: .medium)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
            }
        } accessory: {
            Text(viewModel.remainingText(for: timer))
                .commandlyFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(timer.phase == .completed ? .tertiary : .secondary)
                .monospacedDigit()
                .accessibilityLabel("\(viewModel.remainingText(for: timer)) remaining")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if viewModel.isCreating {
            TimerCreationPane(viewModel: viewModel)
        } else if let timer = viewModel.selectedTimer {
            TimerDetailPane(viewModel: viewModel, timer: timer)
        } else {
            LauncherApplicationEmptyState(
                systemImage: "timer",
                title: "No timer selected",
                message: "Choose a timer or press Command-N to create one."
            )
        }
    }

    private func handleEscape() {
        if viewModel.handleEscape() == false {
            viewModel.goBack()
        }
    }

    private func phaseSystemImage(_ phase: CountdownTimerPhase) -> String {
        switch phase {
        case .ready: return "play.fill"
        case .running: return "hourglass"
        case .paused: return "pause.fill"
        case .completed: return "checkmark"
        }
    }

    private func phaseColor(_ phase: CountdownTimerPhase) -> Color {
        switch phase {
        case .ready: return BrandPalette.accentSoft
        case .running: return BrandPalette.accent
        case .paused: return Color(nsColor: .systemOrange)
        case .completed: return SemanticColors.color(for: .success)
        }
    }
}

private struct TimerCreationPane: View {
    @Bindable var viewModel: TimersViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: density.spacing(.lg)) {
            VStack(spacing: density.spacing(.xs)) {
                Image(systemName: "timer.circle.fill")
                    .commandlyFont(size: 34, weight: .medium)
                    .foregroundStyle(BrandPalette.accent)
                Text("Set the pace")
                    .commandlyFont(size: 18, weight: .semibold)
                Text("Choose a preset or adjust the duration. The countdown starts immediately.")
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: density.spacing(.sm)) {
                ForEach(TimerPreset.allCases) { preset in
                    presetButton(preset)
                }
            }

            VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                Text("Duration")
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(.secondary)

                Stepper(value: $viewModel.draftMinutes, in: 1...1_440) {
                    HStack {
                        Text("\(viewModel.draftMinutes) minutes")
                            .commandlyFont(size: 13, weight: .semibold)
                        Spacer()
                        Text(TimersViewModelDuration.format(minutes: viewModel.draftMinutes))
                            .commandlyFont(size: 11, weight: .medium, design: .monospaced)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Timer duration")
                .accessibilityValue("\(viewModel.draftMinutes) minutes")
                .padding(density.spacing(.sm))
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                        .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                }
            }
            .frame(maxWidth: 310)

            Button("Start Timer") {
                viewModel.startDraftTimer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isDraftValid == false)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("Starts the named timer immediately")
        }
        .padding(density.spacing(.lg))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presetButton(_ preset: TimerPreset) -> some View {
        let isSelected = viewModel.draftName == preset.title
            && viewModel.draftMinutes == preset.minutes
        return Button {
            viewModel.applyPreset(preset)
        } label: {
            VStack(spacing: density.spacing(.xs)) {
                Image(systemName: preset.systemImage)
                    .commandlyFont(size: 18, weight: .semibold)
                    .foregroundStyle(isSelected ? BrandPalette.accent : Color.secondary)
                Text(preset.title)
                    .commandlyFont(size: 11, weight: .semibold)
                Text("\(preset.minutes) min")
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 116, height: 78)
            .background(isSelected ? BrandPalette.accent.opacity(0.10) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                    .strokeBorder(
                        isSelected ? BrandPalette.accent.opacity(0.42) : LauncherPalette.separator,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title), \(preset.minutes) minutes")
    }
}

private struct TimerDetailPane: View {
    @Bindable var viewModel: TimersViewModel
    let timer: CountdownTimer
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: density.spacing(.lg)) {
            VStack(spacing: density.spacing(.xs)) {
                Text(timer.name)
                    .commandlyFont(size: 18, weight: .semibold)
                    .lineLimit(1)
                Text(viewModel.phaseTitle(for: timer.phase).uppercased())
                    .commandlyFont(size: 9, weight: .bold)
                    .tracking(0.8)
                    .foregroundStyle(statusColor)
            }

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: viewModel.elapsedProgress(for: timer))
                    .stroke(
                        statusColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        .linear(duration: MotionDuration.normal.rawValue),
                        value: viewModel.elapsedProgress(for: timer)
                    )

                VStack(spacing: 3) {
                    Text(viewModel.remainingText(for: timer))
                        .commandlyFont(size: 30, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                    Text("remaining")
                        .commandlyFont(size: 9, weight: .medium)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 172, height: 172)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(timer.name), \(viewModel.remainingText(for: timer)) remaining")

            actionButtons

            VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                LauncherApplicationMetadataRow(
                    label: "Duration",
                    value: viewModel.durationText(for: timer)
                )
                LauncherApplicationMetadataRow(
                    label: "Created",
                    value: timer.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
                if let completedAt = timer.completedAt {
                    LauncherApplicationMetadataRow(
                        label: "Finished",
                        value: completedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            .frame(maxWidth: 300)
            .padding(density.spacing(.sm))
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
        }
        .padding(density.spacing(.lg))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionButtons: some View {
        HStack(spacing: density.spacing(.sm)) {
            switch timer.phase {
            case .ready:
                Button("Start", systemImage: "play.fill") {
                    viewModel.startSelected()
                }
                .buttonStyle(.borderedProminent)
            case .running:
                Button("Pause", systemImage: "pause.fill") {
                    viewModel.pauseSelected()
                }
                .buttonStyle(.borderedProminent)
            case .paused:
                Button("Resume", systemImage: "play.fill") {
                    viewModel.startSelected()
                }
                .buttonStyle(.borderedProminent)
            case .completed:
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    viewModel.resetSelected()
                }
                .buttonStyle(.borderedProminent)
            }

            if timer.phase == .running || timer.phase == .paused {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    viewModel.resetSelected()
                }
                .buttonStyle(.bordered)
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                viewModel.deleteSelected()
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }

    private var statusColor: Color {
        switch timer.phase {
        case .ready: return BrandPalette.accentSoft
        case .running: return BrandPalette.accent
        case .paused: return Color(nsColor: .systemOrange)
        case .completed: return SemanticColors.color(for: .success)
        }
    }
}

private enum TimersViewModelDuration {
    static func format(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "00:\(String(format: "%02d", remainder)):00" }
        return "\(hours):\(String(format: "%02d", remainder)):00"
    }
}
