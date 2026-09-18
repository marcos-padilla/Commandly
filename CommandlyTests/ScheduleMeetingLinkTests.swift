import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct ScheduleMeetingLinkTests {
    @Test func extractsDistinctHTTPSChoicesWithoutFollowingLinks() throws {
        let url = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let links = try ScheduleMeetingLinkExtractor.links(
            url: url, location: url.absoluteString,
            notes: "Meeting https://meet.google.com/abc-defg-hij and agenda https://example.com/agenda"
        )
        #expect(links.count == 2)
        #expect(links[0].url == url)
        #expect(links[0].provider == "Google Meet")
        #expect(links[0].supportsAutoJoin)
        #expect(links[1].supportsAutoJoin == false)
    }

    @Test func rejectsUnsafeDestinationsAndConfusableAutojoinHosts() throws {
        for value in [
            "http://meet.google.com/abc-defg-hij", "file:///private/file", "javascript:alert(1)",
            "https://user:password@zoom.us/j/123", "https://127.0.0.1/j/123",
            "https://office.local/j/123", "https://zoom.us:8443/j/123", "https://zoom.us/j/123%0a"
        ] {
            let url = try #require(URL(string: value))
            #expect(ScheduleMeetingLinkExtractor.validated(url) == nil)
        }
        for value in ["https://zoom.us.example.com/j/123", "https://evilzoom.us/j/123", "https://zoom.us/signin"] {
            let url = try #require(URL(string: value))
            #expect(ScheduleMeetingLinkExtractor.validated(url)?.supportsAutoJoin == false)
        }
    }

    @Test func retainsExactMeetingTokenAndBoundsLargeNotes() throws {
        let url = try #require(URL(string: "https://company.zoom.us/j/123?pwd=private%2Btoken"))
        #expect(ScheduleMeetingLinkExtractor.validated(url)?.url.absoluteString == url.absoluteString)
        let links = try ScheduleMeetingLinkExtractor.links(url: nil, location: nil,
            notes: String(repeating: "x", count: 32_768) + " https://meet.google.com/abc-defg-hij")
        #expect(links.isEmpty)
        let many = (0..<30).map { "https://example.com/meeting/\($0)" }.joined(separator: " ")
        #expect(try ScheduleMeetingLinkExtractor.links(url: nil, location: nil, notes: many).count == 16)
    }
}
