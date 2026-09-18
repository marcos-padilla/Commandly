#if DEBUG
import AppKit
import Foundation
import Infrastructure
import SecurityKit

/// Isolated sample data for manual UI validation; never reads the general clipboard or user library.
@MainActor
struct CommandlyProductivityDebugFixture {
    let clipboard: ClipboardHistoryStore
    let library: ProductivityLibraryApplicationServices
    let schedule: ScheduleApplicationServices
    let camera: CameraApplicationServices
    let screenshot: ScreenshotApplicationServices
    let fileBrowser: any FileBrowsing
    let quickAI: QuickAIApplicationServices

    init() {
        self.camera = CameraDebugFixture.services
        self.screenshot = ScreenshotDebugFixture.services
        self.fileBrowser = FileBrowserDebugFixture()
        let chatChoices = [
            QuickAISelection(providerID: "fixture-a", providerName: "Local Fixture", modelID: "sample-a",
                modelName: "Sample A", connectionRevision: "fixture", supportsStreaming: true),
            QuickAISelection(providerID: "fixture-b", providerName: "Local Fixture", modelID: "sample-b",
                modelName: "Sample B", connectionRevision: "fixture", supportsStreaming: true)
        ]
        self.quickAI = QuickAIApplicationServices(chat: InMemoryQuickAIService(
            choices: QuickAICatalog(selections: chatChoices, preferredID: chatChoices.first?.id),
            reply: "This is a generated response for the Commandly UI check. Follow-up messages stay in this temporary chat.",
            discoveredChoices: [QuickAISelection(providerID: "fixture-a", providerName: "Local Fixture",
                modelID: "sample-c", modelName: "Sample C", connectionRevision: "fixture", supportsStreaming: true)]
        ))
        let board = NSPasteboard(name: NSPasteboard.Name("Commandly-UI-Fixture-\(UUID().uuidString)"))
        let clipboard = ClipboardHistoryStore(pasteboard: board)
        _ = clipboard.createTextEntry("A sample paragraph for clipboard organization.")
        _ = clipboard.createTextEntry("A second sample to pin or rename.")
        self.clipboard = clipboard
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            ProductivityLibraryItem(
                id: UUID(), kind: .snippet, title: "Team greeting",
                content: "Hello {{input:Name}},\nToday is {{date}}. {{clipboard}}",
                createdAt: timestamp, updatedAt: timestamp, tags: ["Work", "Writing"]
            ),
            ProductivityLibraryItem(
                id: UUID(), kind: .quickNote, title: "A small idea",
                content: "Make the next useful thing easy to find.",
                createdAt: timestamp, updatedAt: timestamp, tags: ["Personal"]
            )
        ]
        self.library = ProductivityLibraryApplicationServices(
            persistence: InMemoryProductivityLibraryStore(items: items),
            pasteboard: InMemoryPasteboard(initial: "Welcome to the team."),
            urlOpener: NoOpURLOpener()
        )
        let now = Date()
        let meetingStart = now.addingTimeInterval(600)
        let meetingLinks = URL(string: "https://meet.google.com/commandly-sample").map {
            [ScheduleMeetingLink(url: $0, provider: "Google Meet", supportsAutoJoin: true)]
        } ?? []
        let scheduleReader = InMemoryScheduleReader(events: [
            ScheduleEvent(
                id: ScheduleOccurrenceID(calendarID: "work", itemID: "design", occurrenceDate: meetingStart),
                title: "Design review", calendarTitle: "Work",
                startDate: meetingStart, endDate: meetingStart.addingTimeInterval(1800),
                meetingLinks: meetingLinks
            ),
            ScheduleEvent(
                id: ScheduleOccurrenceID(calendarID: "personal", itemID: "walk", occurrenceDate: now),
                title: "A short walk", calendarTitle: "Personal",
                startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(5400)
            )
        ])
        self.schedule = ScheduleApplicationServices(
            reader: scheduleReader,
            permissions: InMemoryPermissionService(states: [.calendar: .authorized]),
            privacySettings: InMemoryPrivacySettingsOpener(),
            autoJoin: ScheduleAutoJoinCoordinator(
                reader: scheduleReader, opener: NoOpURLOpener(),
                scheduler: InMemoryScheduleDeadlineScheduler(), monitor: InMemoryScheduleChangeMonitor()
            ),
            makeChangeMonitor: { InMemoryScheduleChangeMonitor() }
        )
    }
}
#endif
