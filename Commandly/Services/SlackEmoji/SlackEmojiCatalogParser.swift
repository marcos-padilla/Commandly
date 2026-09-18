import Foundation
import Infrastructure

nonisolated enum SlackEmojiURLPolicy {
    static func workspace(_ url: URL) -> Bool {
        guard base(url), let host = url.host?.lowercased(), host.hasSuffix(".slack.com"), host.split(separator: ".").count == 3,
              url.path.isEmpty || url.path == "/", url.query == nil else { return false }
        return true
    }
    static func media(_ url: URL, workspace: SlackEmojiWorkspace) -> Bool {
        guard base(url), let host = url.host?.lowercased(), ["png", "jpg", "jpeg", "gif"].contains(url.pathExtension.lowercased()) else { return false }
        let segments = url.path.split(separator: "/").map(String.init)
        guard !segments.contains(".."), !segments.contains(".") else { return false }
        if host == "emoji.slack-edge.com" {
            return segments.count >= 3 && (segments.first == workspace.id || segments.first == workspace.enterpriseID)
        }
        return (host == workspace.url.host?.lowercased() || host == "my.slack.com") && segments.first == "emoji" && segments.count >= 3
    }
    private static func base(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && url.fragment == nil && url.absoluteString.utf8.count <= 4_096
    }
}
nonisolated enum SlackEmojiCatalogParser {
    static func parse(_ data: Data, workspace: SlackEmojiWorkspace) throws -> [SlackCustomEmoji] {
        guard data.count <= 4 * 1_024 * 1_024 else { throw SlackEmojiError.catalogTooLarge }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw SlackEmojiError.invalidResponse }
        try SlackEmojiAPIValidation.check(ok: response.ok, error: response.error)
        guard let map = response.emoji else { throw SlackEmojiError.invalidResponse }
        guard map.count <= 20_000 else { throw SlackEmojiError.catalogTooLarge }
        guard map.keys.allSatisfy(validName), map.values.allSatisfy({ $0.utf8.count <= 4_096 }) else { throw SlackEmojiError.invalidResponse }
        return try map.keys.sorted().enumerated().map { index, name in
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            var visited: Set<String> = []; var chain: [String] = []; var current = name
            for _ in 0..<64 {
                guard visited.insert(current).inserted else { return .init(name: name, resolution: .aliasCycle) }
                guard let value = map[current] else { return .init(name: name, resolution: .missingAlias) }
                if value.hasPrefix("alias:") {
                    let target = String(value.dropFirst(6))
                    guard validName(target) else { return .init(name: name, resolution: .missingAlias) }
                    chain.append(target); current = target
                } else {
                    guard let url = URL(string: value), SlackEmojiURLPolicy.media(url, workspace: workspace) else { return .init(name: name, resolution: .unsupportedURL) }
                    return .init(name: name, resolution: .image(url: url, canonicalName: current, aliasChain: chain))
                }
            }
            return .init(name: name, resolution: .aliasTooDeep)
        }
    }
    static func validName(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [43, 45, 95].contains($0) }
    }
    static func matches(_ items: [SlackCustomEmoji], query: String) throws -> SlackEmojiMatches {
        guard query.utf8.count <= 512 else { return .init(items: [], total: 0) }
        let words = query.lowercased().replacingOccurrences(of: ":", with: "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        var ranked = [[SlackCustomEmoji](), [SlackCustomEmoji](), [SlackCustomEmoji]()]; var total = 0
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            var terms = item.name.lowercased()
            if case .image(_, let canonical, _) = item.resolution { terms += " " + canonical.lowercased() }
            if words.allSatisfy({ terms.contains($0) }) {
                total += 1
                let rank = phrase.isEmpty || item.name.lowercased() == phrase ? 0 : item.name.lowercased().hasPrefix(phrase) ? 1 : 2
                if ranked[rank].count < 300 { ranked[rank].append(item) }
            }
        }
        return .init(items: Array(ranked.flatMap { $0 }.prefix(300)), total: total)
    }
    private struct Response: Decodable { let ok: Bool; let error: String?; let emoji: [String: String]? }
}
nonisolated enum SlackEmojiAPIValidation {
    static func check(ok: Bool, error: String?) throws {
        guard !ok else { return }
        switch error {
        case "missing_scope": throw SlackEmojiError.missingScope
        case "token_expired", "token_revoked", "account_inactive": throw SlackEmojiError.expired
        case "invalid_auth", "not_authed", "access_denied", "accesslimited", "no_permission", "team_access_not_granted", "not_allowed_token_type": throw SlackEmojiError.denied
        case "ratelimited": throw SlackEmojiError.rateLimited(seconds: 60)
        default: throw SlackEmojiError.unavailable
        }
    }
    static func scopes(_ value: String?) throws {
        guard let value, value.utf8.count <= 4_096 else { throw SlackEmojiError.unverifiedScopes }
        let scopes = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard scopes.contains("emoji:read") else { throw SlackEmojiError.missingScope }
        guard scopes == ["emoji:read"] else { throw SlackEmojiError.excessiveScopes }
    }
}
