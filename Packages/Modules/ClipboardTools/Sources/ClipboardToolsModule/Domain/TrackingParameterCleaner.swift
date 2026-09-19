import Foundation

/// Removes tracking parameters from a URL without changing where it points.
///
/// The cleaner is deliberately conservative. A link that still works after cleaning is the whole
/// point, so a parameter is removed only when it is a well-known analytics tag. Anything the
/// cleaner does not recognise is left alone, because a stripped parameter can silently break a
/// link — a search query, a page number, a signed token — and that is far worse than leaving one
/// tracking tag behind.
///
/// Everything here is a pure transformation over a string. It performs no I/O and never resolves
/// the URL, so it cannot leak the link anywhere.
public struct TrackingParameterCleaner: Sendable {
    /// Exact parameter names removed from any URL.
    ///
    /// Each entry is an analytics identifier with no effect on which page is served.
    public static let defaultParameterNames: Set<String> = [
        // Google / Urchin campaign tags.
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid",
        // Meta.
        "fbclid",
        // Microsoft / Bing.
        "msclkid",
        // X / Twitter.
        "twclid",
        // Yandex.
        "yclid", "_openstat",
        // Mailchimp.
        "mc_cid", "mc_eid",
        // HubSpot.
        "_hsenc", "_hsmi", "hsctatracking",
        // Marketo.
        "mkt_tok",
        // Vero.
        "vero_id", "vero_conv",
        // Olytics.
        "oly_enc_id", "oly_anon_id",
        // Adobe / generic campaign identifiers.
        "icid", "s_kwcid",
        // Instagram / TikTok share identifiers.
        "igshid", "igsh", "ttclid"
    ]

    /// Parameter name prefixes removed from any URL.
    ///
    /// `utm_` covers the whole Urchin family without having to enumerate it.
    public static let defaultParameterPrefixes: [String] = ["utm_"]

    private let parameterNames: Set<String>
    private let parameterPrefixes: [String]

    /// Creates a cleaner.
    ///
    /// - Parameters:
    ///   - additionalParameterNames: extra names the user chose to strip, matched case-insensitively.
    ///   - parameterNames: the built-in exact-match set. Overridable for tests.
    ///   - parameterPrefixes: the built-in prefix set. Overridable for tests.
    public init(
        additionalParameterNames: [String] = [],
        parameterNames: Set<String> = Self.defaultParameterNames,
        parameterPrefixes: [String] = Self.defaultParameterPrefixes
    ) {
        let extra = additionalParameterNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
        self.parameterNames = Set(parameterNames.map { $0.lowercased() }).union(extra)
        self.parameterPrefixes = parameterPrefixes.map { $0.lowercased() }
    }

    /// Whether a query parameter name is considered tracking.
    public func isTracking(parameterNamed name: String) -> Bool {
        let normalized = name.lowercased()
        if parameterNames.contains(normalized) { return true }
        return parameterPrefixes.contains { normalized.hasPrefix($0) }
    }

    /// Returns `text` with tracking parameters removed, or `nil` when nothing changed.
    ///
    /// `nil` means "leave the clipboard alone", which lets a caller report honestly that a link was
    /// already clean instead of rewriting it for no reason.
    ///
    /// Only a single absolute `http` or `https` URL is cleaned. Surrounding whitespace is
    /// preserved so a caller cannot silently reformat the user's text.
    public func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              let queryItems = components.queryItems,
              queryItems.isEmpty == false else {
            return nil
        }

        let kept = queryItems.filter { isTracking(parameterNamed: $0.name) == false }
        guard kept.count != queryItems.count else { return nil }

        // An emptied query must drop the "?" rather than leave a bare one behind.
        components.queryItems = kept.isEmpty ? nil : kept
        guard let cleaned = components.string, cleaned != trimmed else { return nil }
        return cleaned
    }
}
