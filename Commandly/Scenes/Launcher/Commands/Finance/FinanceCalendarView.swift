import DesignSystem
import SwiftUI

struct FinanceCalendarView: View {
    @Bindable var viewModel: FinanceViewModel
    @State private var selectedDate: Date?
    @Environment(\.commandlyLayoutDensity) private var density

    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        VStack(spacing: density.spacing(.xs)) {
            monthHeader
            weekdayHeader
            calendarGrid
            selectedDaySummary
        }
        .padding(density.spacing(.sm))
        .onChange(of: viewModel.displayedMonth) { _, _ in
            selectedDate = nil
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(viewModel.displayedMonth.formatted(.dateTime.month(.wide).year()))
                .commandlyFont(size: 15, weight: .semibold)
            Spacer()
            Button("Today") {
                viewModel.resetMonth()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Button {
                viewModel.moveMonth(offset: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Previous month")
            Button {
                viewModel.moveMonth(offset: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .commandlyFont(size: 8, weight: .bold)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridDates, id: \.self) { date in
                dayCell(date)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let renewals = viewModel.renewals(on: date)
        let isInMonth = calendar.isDate(date, equalTo: viewModel.displayedMonth, toGranularity: .month)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return Button {
            selectedDate = date
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(date.formatted(.dateTime.day()))
                        .commandlyFont(size: 9.5, weight: calendar.isDateInToday(date) ? .bold : .medium)
                        .foregroundStyle(isInMonth ? Color.primary : Color.secondary.opacity(0.55))
                    Spacer(minLength: 0)
                    if renewals.isEmpty == false {
                        Text("\(renewals.count)")
                            .commandlyFont(size: 7.5, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(BrandPalette.accent, in: Capsule())
                    }
                }
                if let first = renewals.first {
                    Text(first.name)
                        .commandlyFont(size: 7.5, weight: .medium)
                        .foregroundStyle(BrandPalette.accentSoft)
                        .lineLimit(1)
                } else {
                    Spacer(minLength: 8)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 41, alignment: .topLeading)
            .background(
                isSelected ? LauncherPalette.selection : LauncherPalette.surface,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        calendar.isDateInToday(date) ? BrandPalette.accent : LauncherPalette.separator,
                        lineWidth: calendar.isDateInToday(date) ? 1.25 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(date, renewals: renewals))
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        if let selectedDate {
            let renewals = viewModel.renewals(on: selectedDate)
            HStack(spacing: density.spacing(.xs)) {
                Text(selectedDate.formatted(date: .long, time: .omitted))
                    .commandlyFont(size: 9.5, weight: .semibold)
                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(width: 1, height: 19)
                if renewals.isEmpty {
                    Text("No renewals")
                        .commandlyFont(size: 9)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(renewals.prefix(3)) { subscription in
                        Button {
                            viewModel.select(subscription)
                            viewModel.selectSection(.subscriptions)
                        } label: {
                            Text("\(subscription.name) · \(viewModel.formattedCurrency(subscription.amount))")
                                .commandlyFont(size: 8.5, weight: .medium)
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(BrandPalette.accent.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(LauncherPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Select a day to inspect its renewals.")
                .commandlyFont(size: 9)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[start...] + symbols[..<start])
    }

    private var gridDates: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: viewModel.displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start) else {
            return []
        }
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstWeek.start)
        }
    }

    private func dayAccessibilityLabel(
        _ date: Date,
        renewals: [FinanceSubscription]
    ) -> String {
        let dateText = date.formatted(date: .long, time: .omitted)
        guard renewals.isEmpty == false else { return "\(dateText), no renewals" }
        let names = renewals.map(\.name).joined(separator: ", ")
        return "\(dateText), \(renewals.count) renewals: \(names)"
    }
}
