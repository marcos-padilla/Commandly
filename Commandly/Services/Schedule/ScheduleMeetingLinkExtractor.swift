import Foundation
import Infrastructure

/// Extracts bounded meeting choices locally. It never fetches, resolves, logs, or opens a URL.
nonisolated enum ScheduleMeetingLinkExtractor {
    static func links(url: URL?, location: String?, notes: String?) throws -> [ScheduleMeetingLink] {
        var candidates = url.map { [$0] } ?? []
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for input in [location, notes].compactMap({ $0 }) {
            let bounded = String(input.prefix(32_768))
            detector.enumerateMatches(
                in: bounded, range: NSRange(bounded.startIndex..., in: bounded)
            ) { match, _, stop in
                if let url = match?.url { candidates.append(url) }
                if candidates.count >= 16 { stop.pointee = true }
            }
            if candidates.count >= 16 { break }
        }
        var seen: Set<URL> = []
        return candidates.prefix(16).compactMap { candidate in
            guard let link = validated(candidate), seen.insert(link.url).inserted else { return nil }
            return link
        }
    }

    static func validated(_ url: URL) -> ScheduleMeetingLink? {
        let raw = url.absoluteString
        guard raw.count <= 8_192,
              let decoded = raw.removingPercentEncoding,
              decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) == false,
              raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) == false,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), host.contains("."),
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) }),
              host.hasSuffix(".local") == false,
              host.allSatisfy({ $0.isNumber || $0 == "." }) == false else { return nil }

        let provider: String
        let supportsAutoJoin: Bool
        let path = components.path.lowercased()
        if host == "meet.google.com" {
            provider = "Google Meet"
            supportsAutoJoin = path.range(of: "^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$", options: .regularExpression) != nil
                || path.hasPrefix("/lookup/")
        } else if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            provider = "Zoom"
            supportsAutoJoin = path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/wc/join/")
        } else if host == "teams.microsoft.com" || host == "teams.live.com" {
            provider = "Microsoft Teams"
            supportsAutoJoin = path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")
        } else if host == "webex.com" || host.hasSuffix(".webex.com") {
            provider = "Webex"
            supportsAutoJoin = path.hasPrefix("/meet/") || path.hasPrefix("/join/")
        } else {
            provider = host
            supportsAutoJoin = false
        }
        return ScheduleMeetingLink(
            url: url,
            provider: provider,
            supportsAutoJoin: supportsAutoJoin
        )
    }
}
