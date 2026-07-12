import Foundation
import SearchKit
import CommandKit

/// Searches registered command manifests.
struct CommandSearchProvider: SearchProviding, Sendable {
    let id = BuiltInSearchProviderID.commands
    private let manifests: [CommandManifest]

    init(manifests: [CommandManifest]) {
        self.manifests = manifests
    }

    func search(_ query: SearchQuery) async throws -> SearchResult {
        try Task.checkCancellation()
        var items: [SearchItem] = []
        for manifest in manifests {
            try Task.checkCancellation()
            guard let score = SearchMatchScorer.score(
                query: query.text,
                title: manifest.title,
                subtitle: manifest.subtitle,
                keywords: manifest.keywords
            ) else {
                continue
            }
            // Prefer commands slightly over empty-query baseline peers.
            let adjusted = query.isEmpty ? score + 0.05 : score
            items.append(
                SearchItem(
                    id: manifest.id.rawValue,
                    title: manifest.title,
                    subtitle: manifest.subtitle,
                    providerID: id,
                    score: adjusted
                )
            )
        }
        return SearchResult(query: query, items: items)
    }
}

/// Searches installed applications.
struct ApplicationSearchProvider: SearchProviding, Sendable {
    let id = BuiltInSearchProviderID.applications
    private let applications: [InstalledApplicationSnapshot]
    private let favoriteBundleIDs: Set<String>
    private let disabledBundleIDs: Set<String>
    private let ranking: [String: AppUsageRanking]

    init(
        applications: [InstalledApplicationSnapshot],
        favoriteBundleIDs: Set<String> = [],
        disabledBundleIDs: Set<String> = [],
        ranking: [String: AppUsageRanking] = [:]
    ) {
        self.applications = applications
        self.favoriteBundleIDs = favoriteBundleIDs
        self.disabledBundleIDs = disabledBundleIDs
        self.ranking = ranking
    }

    func search(_ query: SearchQuery) async throws -> SearchResult {
        try Task.checkCancellation()
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [SearchItem] = []
        for app in applications {
            try Task.checkCancellation()
            let disabled = disabledBundleIDs.contains(app.bundleIdentifier)
            if disabled && trimmed.isEmpty {
                continue
            }
            guard let baseScore = SearchMatchScorer.score(
                query: query.text,
                title: app.name,
                subtitle: app.bundleIdentifier,
                keywords: [app.name]
            ) else {
                continue
            }
            var score = baseScore
            if favoriteBundleIDs.contains(app.bundleIdentifier) {
                score += 0.18
            }
            let usage = ranking[app.bundleIdentifier] ?? .empty
            if usage.openCount > 0 {
                score += min(0.2, Double(usage.openCount) * 0.02)
            }
            items.append(
                SearchItem(
                    id: app.bundleIdentifier,
                    title: app.name,
                    subtitle: app.bundleIdentifier,
                    providerID: id,
                    score: score
                )
            )
        }
        return SearchResult(query: query, items: items)
    }
}

/// Searches honest placeholder / soon rows.
struct PlaceholderSearchProvider: SearchProviding, Sendable {
    let id = BuiltInSearchProviderID.placeholders
    private let placeholders: [PlaceholderSearchRecord]

    init(placeholders: [PlaceholderSearchRecord]) {
        self.placeholders = placeholders
    }

    func search(_ query: SearchQuery) async throws -> SearchResult {
        try Task.checkCancellation()
        // Demote placeholders when the user is actively searching.
        let demotion = query.isEmpty ? 0.0 : 0.25
        var items: [SearchItem] = []
        for placeholder in placeholders {
            try Task.checkCancellation()
            guard let score = SearchMatchScorer.score(
                query: query.text,
                title: placeholder.title,
                subtitle: placeholder.subtitle,
                keywords: placeholder.keywords
            ) else {
                continue
            }
            items.append(
                SearchItem(
                    id: placeholder.id,
                    title: placeholder.title,
                    subtitle: placeholder.subtitle,
                    providerID: id,
                    score: max(0.01, score - demotion)
                )
            )
        }
        return SearchResult(query: query, items: items)
    }
}

/// Sendable snapshot of an installed app for search providers.
struct InstalledApplicationSnapshot: Sendable, Equatable {
    let bundleIdentifier: String
    let name: String
    let path: String
}

/// Sendable snapshot of a placeholder row for search.
struct PlaceholderSearchRecord: Sendable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let keywords: [String]
    let systemImage: String
    let badge: LauncherItemBadge
    let section: LauncherSectionKind
    let message: String
}

/// Merges provider results by score with cancellation support.
struct CompositeSearchService: Sendable {
    private let providers: [any SearchProviding]

    init(providers: [any SearchProviding]) {
        self.providers = providers
    }

    func search(_ query: SearchQuery) async throws -> SearchResult {
        try Task.checkCancellation()
        var merged: [SearchItem] = []
        for provider in providers {
            try Task.checkCancellation()
            let result = try await provider.search(query)
            merged.append(contentsOf: result.items)
        }
        let sorted = merged.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
        let limited: [SearchItem]
        if let limit = query.limit {
            limited = Array(sorted.prefix(limit))
        } else {
            limited = sorted
        }
        return SearchResult(query: query, items: limited, isComplete: true)
    }
}
