import DesignSystem
import SwiftUI

/// Controls tab: the behaviors Commandly can switch on and off, grouped the way they are used.
struct ControlsPanelSection: View {
    @Bindable var model: ControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
            ForEach(model.groups) { group in
                groupView(group)
            }

            if let message = model.errorMessage {
                Text(message)
                    .commandlyFont(size: 10)
                    .foregroundStyle(SemanticColors.color(for: .danger))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .onAppear { model.addObserver() }
        .onDisappear { model.removeObserver() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controls")
    }

    // MARK: - Groups

    private func groupView(_ group: ControlGroupPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            groupHeader(group)

            if model.isCollapsed(group.group) == false {
                ForEach(group.rows) { row in
                    rowView(row)
                }
            }
        }
    }

    private func groupHeader(_ group: ControlGroupPresentation) -> some View {
        Button {
            withAnimation(CommandlyMotion.control) {
                model.toggleCollapsed(group.group)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .commandlyFont(size: 9, weight: .bold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(model.isCollapsed(group.group) ? 0 : 90))
                    .accessibilityHidden(true)

                Text(group.group.title.uppercased())
                    .commandlyFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .kerning(0.6)

                Spacer(minLength: Spacing.xs.rawValue)

                Text(group.countLabel)
                    .commandlyFont(size: 10.5, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(group.enabledCount > 0 ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.group.title)
        .accessibilityValue("\(group.enabledCount) of \(group.switchableCount) on")
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: ControlPresentation) -> some View {
        if row.isNested {
            nestedRow(row)
        } else {
            cardRow(row)
        }
    }

    private func cardRow(_ row: ControlPresentation) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm.rawValue) {
            Image(systemName: row.control.symbolName)
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(row.isEnabled && row.isOn ? Color.accentColor : Color.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.control.title)
                    .commandlyFont(size: 12.5, weight: .semibold)
                    .foregroundStyle(row.isEnabled ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.caption(for: row))
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs.rawValue)

            control(row)
        }
        .statusPanelCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.control.title)
        .accessibilityHint(model.caption(for: row))
    }

    /// A sub-option belongs to the row above it, so it sits inside that row's margin without a
    /// card of its own.
    private func nestedRow(_ row: ControlPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs.rawValue) {
                Text(row.control.title)
                    .commandlyFont(size: 11.5, weight: .medium)
                    .foregroundStyle(row.isEnabled ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.xs.rawValue)
                control(row)
            }
            Text(model.caption(for: row))
                .commandlyFont(size: 9.5)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.sm.rawValue)
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.control.title)
    }

    @ViewBuilder
    private func control(_ row: ControlPresentation) -> some View {
        if row.isEnabled {
            Toggle(
                "",
                isOn: Binding(
                    get: { row.isOn },
                    set: { model.setOn($0, for: row.control) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(row.control.title)
        } else {
            Toggle("", isOn: .constant(false))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(true)
                .accessibilityHidden(true)
        }
    }
}
