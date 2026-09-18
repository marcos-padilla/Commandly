import DesignSystem
import Infrastructure
import SwiftUI

struct ScheduleMeetingReview: View {
    @Bindable var viewModel: ScheduleViewModel
    let event: ScheduleEvent
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.spacing(.md)) {
                Text(viewModel.joinMode == .manual ? "Review meeting link" : "Enable automatic joining")
                    .commandlyFont(size: 18, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(event.title).commandlyFont(size: 14, weight: .medium)
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                    .commandlyFont(size: 12).foregroundStyle(.secondary)
                if event.meetingLinks.count > 1 {
                    Picker("Meeting link", selection: $viewModel.selectedLinkID) {
                        ForEach(event.meetingLinks) { link in
                            Text(link.provider + " · " + (link.url.host ?? "")).tag(Optional(link.id))
                        }
                    }.accessibilityLabel("Choose meeting destination")
                }
                if let link = viewModel.reviewedLink {
                    Label(link.provider, systemImage: "link").commandlyFont(size: 12, weight: .medium)
                    Text(link.url.absoluteString)
                        .commandlyFont(size: 11, design: .monospaced).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(density.spacing(.sm))
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                Text(viewModel.joinMode == .manual
                     ? "Join opens this exact link in its default application. The latest event is checked again first."
                     : "Commandly will open this exact link at the event's start time while the app stays running. Only this occurrence is armed; the event and link stay in memory. You can cancel from My Schedule.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary)
                if viewModel.joinMode == .automatic {
                    if viewModel.autoJoinPlan != nil {
                        Text("This replaces the meeting currently armed for automatic joining.")
                            .commandlyFont(size: 11, weight: .medium)
                    }
                    if viewModel.canConfirm == false {
                        Text("Automatic joining needs a future timed event with a Google Meet, Zoom, Microsoft Teams, or Webex link. Other HTTPS links can be joined manually.")
                            .commandlyFont(size: 11).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Cancel", action: viewModel.cancelReview).buttonStyle(.borderless)
                    Spacer()
                    Button(viewModel.joinMode == .manual ? "Join Meeting" : "Enable Autojoin", action: viewModel.confirmReview)
                        .buttonStyle(.borderedProminent).disabled(viewModel.canConfirm == false)
                }
            }.padding(density.spacing(.lg))
        }
    }
}
