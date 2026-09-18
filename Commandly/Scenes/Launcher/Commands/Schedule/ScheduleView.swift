import DesignSystem
import Infrastructure
import SwiftUI

struct ScheduleView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Search events and calendars…",
            searchAccessibilityIdentifier: "schedule-query",
            onBack: viewModel.goBack,
            onSubmit: viewModel.performPrimary,
            onMoveSelection: viewModel.moveSelection,
            onEscape: { if viewModel.handleEscape() == false { viewModel.goBack() } }
        ) {
            CommandlyOptionMenu(
                items: ScheduleRange.allCases.map { CommandlyOptionItem(id: $0.id, title: $0.title) },
                selectionID: viewModel.range.id,
                accessibilityLabelText: "Schedule date range"
            ) { item in
                if let range = ScheduleRange(rawValue: item.id) { viewModel.range = range }
            }
            if viewModel.calendarOptions.isEmpty == false {
                CommandlyOptionMenu(
                    items: [CommandlyOptionItem(id: "all", title: "All Calendars")]
                        + viewModel.calendarOptions.map { CommandlyOptionItem(id: "calendar:" + $0.id, title: $0.title) },
                    selectionID: viewModel.selectedCalendarID.map { "calendar:" + $0 } ?? "all",
                    accessibilityLabelText: "Schedule calendar filter"
                ) { item in
                    viewModel.selectedCalendarID = item.id == "all" ? nil : String(item.id.dropFirst("calendar:".count))
                }
            }
        } sidebar: {
            agenda
        } detail: {
            detail
        }
        .onAppear { viewModel.start() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("My Schedule")
    }

    private var agenda: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.xs)) {
                    if let plan = viewModel.autoJoinPlan {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Autojoin armed", systemImage: "clock.badge.checkmark")
                                .commandlyFont(size: 11, weight: .semibold)
                            Text(plan.event.title).commandlyFont(size: 11).lineLimit(2)
                            Text(plan.event.startDate, style: .time).commandlyFont(size: 11)
                            Button("Cancel Automatic Joining", action: viewModel.cancelAutoJoin)
                                .buttonStyle(.borderless)
                                .commandlyFont(size: 10)
                        }
                        .padding(density.spacing(.sm))
                        Divider()
                    }
                    if viewModel.phase == .loading {
                        ProgressView("Loading schedule…")
                            .frame(maxWidth: .infinity).padding(density.spacing(.md))
                    }
                    if viewModel.isTruncated {
                        Text("More events are available. Try a shorter date range.")
                            .commandlyFont(size: 11).foregroundStyle(.secondary)
                            .padding(density.spacing(.sm))
                    }
                    ForEach(viewModel.filteredEvents) { event in
                        LauncherApplicationRow(
                            isSelected: viewModel.selectedEvent?.id == event.id,
                            onSelect: { viewModel.select(event.id) },
                            onHoverChange: { _ in }
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(event.title).commandlyFont(size: 12, weight: .semibold).lineLimit(2)
                                    Spacer(minLength: 0)
                                    if event.meetingLinks.isEmpty == false {
                                        Image(systemName: "video").accessibilityHidden(true)
                                    }
                                }
                                Text(event.startDate.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened))
                                    .commandlyFont(size: 10).foregroundStyle(.secondary)
                                Text(event.isAllDay ? "All day · " + event.calendarTitle : event.calendarTitle)
                                    .commandlyFont(size: 10).foregroundStyle(.secondary).lineLimit(1)
                                if event.isCancelled || event.isDeclined {
                                    Text(event.isCancelled ? "Canceled" : "Declined")
                                        .commandlyFont(size: 10, weight: .medium).foregroundStyle(.secondary)
                                }
                            }
                        } accessory: { EmptyView() }
                        .id(event.id)
                        .accessibilityElement(children: .combine)
                    }
                    if viewModel.phase == .ready && viewModel.filteredEvents.isEmpty {
                        Text("No upcoming events match these filters.")
                            .commandlyFont(size: 12).foregroundStyle(.secondary)
                            .padding(density.spacing(.md))
                    }
                }
                .padding(density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if viewModel.phase == .accessRequired {
            VStack(spacing: density.spacing(.md)) {
                Image(systemName: "calendar.badge.exclamationmark").commandlyFont(size: 30)
                Text("Your calendar, within reach").commandlyFont(size: 18, weight: .semibold)
                Text("Allow Calendar access to see upcoming events and review meeting links. macOS calls this Full Access; My Schedule only reads events and keeps their details on this Mac.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(viewModel.accessActionTitle, action: viewModel.requestAccess)
                    .buttonStyle(.borderedProminent).disabled(viewModel.isPerforming)
            }
            .padding(density.spacing(.lg)).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.phase == .failed {
            VStack(spacing: density.spacing(.md)) {
                LauncherApplicationEmptyState(systemImage: "calendar.badge.exclamationmark", title: "Schedule unavailable",
                    message: viewModel.errorMessage ?? "Try refreshing.")
                Button("Try Again", action: viewModel.refresh).buttonStyle(.borderedProminent)
            }.padding(density.spacing(.md))
        } else if let event = viewModel.reviewEvent {
            ScheduleMeetingReview(viewModel: viewModel, event: event)
        } else if let event = viewModel.selectedEvent {
            eventDetails(event)
        } else {
            LauncherApplicationEmptyState(systemImage: "calendar", title: "My Schedule",
                message: viewModel.phase == .loading ? "Loading your upcoming events…" : "Your next events and meeting links will appear here.")
        }
    }

    private func eventDetails(_ event: ScheduleEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                Label(event.calendarTitle, systemImage: "calendar")
                    .commandlyFont(size: 11, weight: .medium).foregroundStyle(.secondary)
                Text(event.title).commandlyFont(size: 21, weight: .semibold).textSelection(.enabled)
                Text(event.startDate.formatted(date: .complete, time: event.isAllDay ? .omitted : .shortened))
                    .commandlyFont(size: 13)
                Text(event.isAllDay ? "All-day event" : "Ends " + event.endDate.formatted(date: .abbreviated, time: .shortened))
                    .commandlyFont(size: 12).foregroundStyle(.secondary)
                if let location = event.location, location.isEmpty == false {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .commandlyFont(size: 12).textSelection(.enabled)
                }
                if event.isCancelled || event.isDeclined {
                    Text(event.isCancelled ? "This event is canceled." : "You declined this event.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary)
                } else if event.meetingLinks.isEmpty {
                    Text("No supported HTTPS links were found in this event.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary)
                } else {
                    Divider()
                    Text("Meeting links").commandlyFont(size: 12, weight: .semibold)
                    ForEach(event.meetingLinks) { link in
                        Label(link.provider, systemImage: "video")
                            .commandlyFont(size: 12)
                    }
                    Button("Review Meeting Link") { viewModel.prepareReview(mode: .manual) }
                        .buttonStyle(.borderedProminent)
                    Button("Automatically Join This Occurrence…") { viewModel.prepareReview(mode: .automatic) }
                        .buttonStyle(.borderless)
                    Text("Links open only after you review and choose Join. Automatic joining is off until you enable it for this occurrence.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(density.spacing(.lg))
        }
    }
}
