import AppKit
import DesignSystem
import SwiftUI

/// Keep Awake tab: the session switch, its duration, and every option behind it.
struct KeepAwakePanelSection: View {
    @Bindable var coordinator: KeepAwakeCoordinator
    @State private var optionsExpanded = false
    @State private var automationExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            if coordinator.isActive, coordinator.endDate != nil {
                extendRow
            }

            if coordinator.isActive == false {
                durationRow
            }

            optionsDisclosure

            Divider()

            batteryFloorRow
        }
        .statusPanelCard()
        .onAppear {
            coordinator.refreshAccessibilityPermission()
        }
    }

    // MARK: - Session

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs.rawValue) {
            statusText
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xs.rawValue)
            Toggle("", isOn: sessionBinding)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Keep Awake")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if coordinator.isActive {
            if coordinator.isPausedForScreenLock {
                Text("Paused while the screen is locked.")
            } else if coordinator.trigger == .automation {
                Text(automationStatusText)
            } else if let endDate = coordinator.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Ends in \(KeepAwakeAutomationRules.remainingText(until: endDate, now: context.date))")
                }
            } else {
                Text("Awake until you switch this off.")
            }
        } else {
            Text("The Mac follows its normal energy rules.")
        }
    }

    private var automationStatusText: String {
        let titles = KeepAwakeAutomationCondition.allCases
            .filter(coordinator.activeConditions.contains)
            .map(\.title)
        guard titles.isEmpty == false else { return "Awake automatically." }
        return "Awake automatically: \(ListFormatter.localizedString(byJoining: titles).lowercased())."
    }

    private var sessionBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isActive },
            set: { isOn in
                if isOn {
                    coordinator.activate(minutes: coordinator.settings.duration)
                } else if coordinator.isActive {
                    coordinator.stopByHand()
                }
            }
        )
    }

    private var extendRow: some View {
        HStack(spacing: 6) {
            ForEach([15, 30, 60], id: \.self) { minutes in
                Button("+\(minutes) min") {
                    coordinator.extend(minutes: minutes)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .commandlyFont(size: 10)
                .accessibilityLabel("Extend by \(minutes) minutes")
            }
            Spacer(minLength: 0)
        }
    }

    private var durationRow: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("Duration")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("Duration", selection: $coordinator.settings.duration) {
                ForEach(KeepAwakeAutomationRules.allowedDurations, id: \.self) { minutes in
                    Text(KeepAwakeAutomationRules.durationTitle(minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }

    // MARK: - Options

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            StatusPanelDisclosureHeader(title: "Options", isExpanded: $optionsExpanded)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                    KeepAwakeIconPicker(
                        icon: $coordinator.settings.activeIcon,
                        tint: $coordinator.settings.activeIconTint
                    )

                    StatusPanelToggleRow(
                        symbolName: "display",
                        title: "Allow the display to sleep",
                        isOn: $coordinator.settings.allowsDisplaySleep
                    )

                    StatusPanelToggleRow(
                        symbolName: "play.circle",
                        title: "Keep Awake when Commandly opens",
                        isOn: $coordinator.settings.startsWithCommandly
                    )

                    automationDisclosure

                    StatusPanelToggleRow(
                        symbolName: "cursorarrow.motionlines",
                        title: "Move pointer slightly",
                        caption: pointerCaption,
                        captionIsWarning: coordinator.pointerNudgeNeedsAccessibility,
                        isOn: $coordinator.settings.nudgesPointer
                    )

                    if coordinator.settings.nudgesPointer {
                        pointerIntervalRow

                        if coordinator.pointerNudgeNeedsAccessibility {
                            Button("Grant Accessibility Access") {
                                coordinator.requestAccessibilityPermission()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.leading, 22)
                        }
                    }
                }
                .padding(.leading, 19)
                .transition(.opacity)
            }
        }
    }

    private var pointerCaption: String {
        coordinator.pointerNudgeNeedsAccessibility
            ? "Needs Accessibility permission to move the pointer."
            : "Nudges the pointer one point so apps see activity."
    }

    private var pointerIntervalRow: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text("Every")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("Pointer nudge interval", selection: $coordinator.settings.pointerNudgeInterval) {
                ForEach(KeepAwakeAutomationRules.allowedPointerNudgeIntervals, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.leading, 22)
    }

    // MARK: - Automation

    private var automationDisclosure: some View {
        VStack(alignment: .leading, spacing: 7) {
            StatusPanelDisclosureHeader(
                title: "Automation",
                symbolName: "bolt.fill",
                isExpanded: $automationExpanded
            ) {
                automationSummary
            }

            if automationExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                    KeepAwakeAutomationEditor(coordinator: coordinator)

                    StatusPanelToggleRow(
                        symbolName: "lock.fill",
                        title: "Pause while the screen is locked",
                        isOn: $coordinator.settings.pausesWhenScreenLocked
                    )
                }
                .padding(.leading, 22)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var automationSummary: some View {
        if coordinator.settings.hasAutomation {
            HStack(spacing: 4) {
                if coordinator.settings.startsWithExternalDisplay { summaryBadge("display") }
                if coordinator.settings.startsWhenConnectedToPower { summaryBadge("powerplug.fill") }
                if coordinator.settings.startsWithRunningApplications { summaryBadge("app.fill") }
                if coordinator.settings.pausesWhenScreenLocked { summaryBadge("lock.fill") }
            }
            .accessibilityHidden(true)
        } else {
            Text("Off")
                .commandlyFont(size: 9.5, weight: .medium)
                .foregroundStyle(.tertiary)
        }
    }

    private func summaryBadge(_ symbolName: String) -> some View {
        Image(systemName: symbolName)
            .commandlyFont(size: 9, weight: .semibold)
            .foregroundStyle(Color.accentColor)
            .frame(width: 17, height: 17)
            .background(Circle().fill(Color.accentColor.opacity(0.14)))
    }

    // MARK: - Battery floor

    private var batteryFloorRow: some View {
        HStack(alignment: .top, spacing: Spacing.xs.rawValue) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Stop on low battery")
                    .commandlyFont(size: 12)
                Text(batteryCaption)
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Stop on low battery", selection: $coordinator.settings.batteryFloorPercent) {
                ForEach(KeepAwakeAutomationRules.allowedBatteryFloors, id: \.self) { percent in
                    Text(percent == 0 ? "Never" : "\(percent)%").tag(percent)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var batteryCaption: String {
        guard coordinator.settings.batteryFloorPercent > 0 else {
            return "A session runs on battery until you end it."
        }
        if let percent = coordinator.batteryPercentRemaining {
            return "Ends the session at \(coordinator.settings.batteryFloorPercent)%. Battery is at \(percent)%."
        }
        return "Ends the session at \(coordinator.settings.batteryFloorPercent)% on battery."
    }
}
