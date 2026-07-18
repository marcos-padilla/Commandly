import CommandKit
import Foundation
import Infrastructure

/// Immutable page content resolved once for one invocation. Runtime usage/catalog changes cannot
/// reorder it while the pointer is moving.
nonisolated struct CommandWheelFrozenPage: Sendable, Equatable {
    let id: UUID
    let name: String
    let segments: [CommandWheelPresentedSegment]
}

nonisolated struct CommandWheelFrozenContent: Sendable, Equatable {
    let pagesByID: [UUID: CommandWheelFrozenPage]
    let parentPageByID: [UUID: UUID]

    func page(id: UUID) -> CommandWheelFrozenPage? {
        pagesByID[id]
    }
}

nonisolated protocol CommandWheelContentFreezing: Sendable {
    func freeze(profile: CommandWheelProfile) async throws -> CommandWheelFrozenContent
}

/// Resolves command manifests/availability and expands history-backed dynamic providers before the
/// wheel is presented. It deliberately never executes commands or writes usage history.
nonisolated struct DefaultCommandWheelContentFreezer: CommandWheelContentFreezing {
    /// History is already durably bounded, but one provider should not resolve the entire history
    /// before it can show a handful of slots. The scan window is deliberately larger than the
    /// maximum 12 visible slots so invalid/non-replayable entries can still be skipped first.
    private static let maximumDynamicCandidateScanCount = 96

    private let resolver: any CommandResolving
    private let usageHistory: any CommandUsageHistoryStoring
    private let installedApplicationQuery: any InstalledApplicationQuerying

    init(
        resolver: any CommandResolving,
        usageHistory: any CommandUsageHistoryStoring,
        installedApplicationQuery: any InstalledApplicationQuerying =
            InMemoryInstalledApplicationQuery()
    ) {
        self.resolver = resolver
        self.usageHistory = usageHistory
        self.installedApplicationQuery = installedApplicationQuery
    }

    func freeze(profile: CommandWheelProfile) async throws -> CommandWheelFrozenContent {
        try Task.checkCancellation()
        let hasDynamicProviders = profile.pages.contains { page in
            page.segments.contains { segment in
                if case .dynamicProvider = segment.content { return true }
                return false
            }
        }
        let hasInstalledApplicationReferences = profile.pages.contains { page in
            page.segments.contains { segment in
                guard case .command(let reference) = segment.content else { return false }
                return installedApplicationBundleIdentifier(reference) != nil
            }
        }
        async let usageTask: [CommandUsageSummary] = hasDynamicProviders
            ? usageHistory.allSummaries() : []
        async let applicationsTask: [InstalledApplication] = hasInstalledApplicationReferences
            ? installedApplicationQuery.installedApplications() : []
        let (usageSummaries, installedApplications) = await (usageTask, applicationsTask)
        try Task.checkCancellation()
        var installedApplicationsByBundleID = [String: InstalledApplication]()
        for application in installedApplications {
            let key = normalizedBundleIdentifier(application.bundleIdentifier)
            if key.isEmpty == false, installedApplicationsByBundleID[key] == nil {
                installedApplicationsByBundleID[key] = application
            }
        }
        var pagesByID = [UUID: CommandWheelFrozenPage]()
        var parentPageByID = [UUID: UUID]()
        var resolutionCache = CommandResolutionCache()

        // Resolve the root first so the user-facing page owns the earliest bounded work.
        let orderedPages = profile.pages.filter { $0.id == profile.rootPageID }
            + profile.pages.filter { $0.id != profile.rootPageID }
        for page in orderedPages {
            try Task.checkCancellation()
            let segments = try await freeze(
                page: page,
                profile: profile,
                usageSummaries: usageSummaries,
                installedApplicationsByBundleID: installedApplicationsByBundleID,
                resolutionCache: &resolutionCache
            )
            pagesByID[page.id] = CommandWheelFrozenPage(
                id: page.id,
                name: page.name,
                segments: segments
            )
            for segment in page.segments {
                if case .submenu(let childPageID) = segment.content,
                   parentPageByID[childPageID] == nil {
                    parentPageByID[childPageID] = page.id
                }
            }
        }

        return CommandWheelFrozenContent(
            pagesByID: pagesByID,
            parentPageByID: parentPageByID
        )
    }

    private func freeze(
        page: CommandWheelPage,
        profile: CommandWheelProfile,
        usageSummaries: [CommandUsageSummary],
        installedApplicationsByBundleID: [String: InstalledApplication],
        resolutionCache: inout CommandResolutionCache
    ) async throws -> [CommandWheelPresentedSegment] {
        let slotCount = profile.interaction.visibleSlotCount
        let configured = page.segments
            .filter { (0 ..< slotCount).contains($0.slotIndex) }
            .sorted {
                if $0.slotIndex != $1.slotIndex { return $0.slotIndex < $1.slotIndex }
                return $0.id.uuidString < $1.id.uuidString
            }
        let dynamicSegments = configured.filter {
            if case .dynamicProvider = $0.content { return true }
            return false
        }
        let staticSegments = configured.filter {
            if case .dynamicProvider = $0.content { return false }
            return true
        }

        var frozenBySlot = [Int: CommandWheelPresentedSegment]()
        var representedCommandIDs = Set<CommandID>()
        for segment in staticSegments where frozenBySlot[segment.slotIndex] == nil {
            try Task.checkCancellation()
            let frozen = try await freezeStatic(
                segment: segment,
                page: page,
                profile: profile,
                installedApplicationsByBundleID: installedApplicationsByBundleID,
                resolutionCache: &resolutionCache
            )
            if shouldInclude(frozen, profile: profile) {
                frozenBySlot[segment.slotIndex] = frozen
                if case .command(let reference) = frozen.kind {
                    representedCommandIDs.insert(reference.commandID)
                }
            }
        }

        for segment in dynamicSegments {
            try Task.checkCancellation()
            guard case .dynamicProvider(let provider) = segment.content else { continue }
            guard CommandWheelDynamicProviderID.supported.contains(provider.providerID) else {
                let failed = dynamicPlaceholder(
                    segment: segment,
                    pageID: page.id,
                    slotIndex: segment.slotIndex,
                    state: .error,
                    title: segment.customLabel ?? "Provider unavailable",
                    systemImage: segment.customIcon?.systemSymbolName ?? "exclamationmark.triangle",
                    usesCustomIcon: validCustomIconName(segment) != nil
                )
                if frozenBySlot[segment.slotIndex] == nil,
                   shouldInclude(failed, profile: profile) {
                    frozenBySlot[segment.slotIndex] = failed
                }
                continue
            }

            let maximumCount = min(max(0, provider.maximumResultCount), slotCount)
            let scanCount = min(
                Self.maximumDynamicCandidateScanCount,
                max(32, maximumCount * 8)
            )
            let ordered = orderedSummaries(usageSummaries, provider: provider)
                .filter { representedCommandIDs.contains($0.commandID) == false }
            var candidates = [DynamicCandidate]()
            for summary in ordered.prefix(scanCount) {
                try Task.checkCancellation()
                let reference = CommandReference(commandID: summary.commandID)
                let presented = try await freezeCommand(
                    reference: reference,
                    sourceSegment: segment,
                    pageID: page.id,
                    slotIndex: segment.slotIndex,
                    isDynamic: true,
                    installedApplicationsByBundleID: installedApplicationsByBundleID,
                    resolutionCache: &resolutionCache
                )
                // Usage history deliberately retains only command identifiers, never arguments.
                // A command that cannot resolve from an empty reference is therefore not safely
                // replayable by this provider. Skip it before applying the provider limit so a
                // parameterized history entry cannot crowd out a lower-ranked reusable command.
                if isReplayableDynamicCandidate(presented),
                   shouldInclude(presented, profile: profile) {
                    candidates.append(DynamicCandidate(summary: summary, segment: presented))
                }
            }
            if provider.sortingMethod == .alphabetical {
                candidates.sort {
                    let left = $0.segment.title.localizedCaseInsensitiveCompare($1.segment.title)
                    if left != .orderedSame { return left == .orderedAscending }
                    return $0.summary.commandID.rawValue < $1.summary.commandID.rawValue
                }
            }

            let freeSlots = clockwiseFreeSlots(
                startingAt: segment.slotIndex,
                slotCount: slotCount,
                occupied: Set(frozenBySlot.keys)
            )
            var insertedCount = 0
            for (candidate, slotIndex) in zip(candidates.prefix(maximumCount), freeSlots) {
                var value = candidate.segment
                value = CommandWheelPresentedSegment(
                    sourceSegmentID: value.sourceSegmentID,
                    pageID: value.pageID,
                    slotIndex: slotIndex,
                    kind: value.kind,
                    state: value.state,
                    title: value.title,
                    subtitle: value.subtitle,
                    systemImage: value.systemImage,
                    isDynamic: true,
                    usesCustomIcon: value.usesCustomIcon,
                    applicationIconPath: value.applicationIconPath
                )
                frozenBySlot[slotIndex] = value
                representedCommandIDs.insert(candidate.summary.commandID)
                insertedCount += 1
            }

            if provider.emptyState == .showEmptySlots, insertedCount < maximumCount {
                let remainingFreeSlots = clockwiseFreeSlots(
                    startingAt: segment.slotIndex,
                    slotCount: slotCount,
                    occupied: Set(frozenBySlot.keys)
                )
                for slotIndex in remainingFreeSlots.prefix(maximumCount - insertedCount) {
                    frozenBySlot[slotIndex] = dynamicPlaceholder(
                        segment: segment,
                        pageID: page.id,
                        slotIndex: slotIndex,
                        state: .empty,
                        title: segment.customLabel ?? "No commands yet",
                        systemImage: segment.customIcon?.systemSymbolName ?? "clock",
                        usesCustomIcon: validCustomIconName(segment) != nil
                    )
                }
            }
        }

        return frozenBySlot.values.sorted { $0.slotIndex < $1.slotIndex }
    }

    private func freezeStatic(
        segment: CommandWheelSegment,
        page: CommandWheelPage,
        profile: CommandWheelProfile,
        installedApplicationsByBundleID: [String: InstalledApplication],
        resolutionCache: inout CommandResolutionCache
    ) async throws -> CommandWheelPresentedSegment {
        switch segment.content {
        case .command(let reference):
            return try await freezeCommand(
                reference: reference,
                sourceSegment: segment,
                pageID: page.id,
                slotIndex: segment.slotIndex,
                isDynamic: false,
                installedApplicationsByBundleID: installedApplicationsByBundleID,
                resolutionCache: &resolutionCache
            )

        case .submenu(let childPageID):
            let childPage = profile.pages.first { $0.id == childPageID }
            let state: CommandWheelPresentedSegmentState
            if childPage == nil {
                state = .missing
            } else if profile.interaction.submenuActivationBehavior == .disabled {
                state = .unavailable(.disabled)
            } else {
                state = .available
            }
            return CommandWheelPresentedSegment(
                sourceSegmentID: segment.id,
                pageID: page.id,
                slotIndex: segment.slotIndex,
                kind: .submenu(pageID: childPageID),
                state: state,
                title: normalized(segment.customLabel) ?? childPage?.name ?? "Missing submenu",
                subtitle: childPage == nil ? "Page is unavailable" : "Submenu",
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    normalized(segment.customIcon?.systemSymbolName),
                    fallback: "square.stack.3d.up"
                ),
                isDynamic: false,
                usesCustomIcon: validCustomIconName(segment) != nil
            )

        case .empty:
            return CommandWheelPresentedSegment(
                sourceSegmentID: segment.id,
                pageID: page.id,
                slotIndex: segment.slotIndex,
                kind: .empty,
                state: .empty,
                title: normalized(segment.customLabel) ?? "Empty slot",
                subtitle: nil,
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    normalized(segment.customIcon?.systemSymbolName),
                    fallback: "circle.dashed"
                ),
                isDynamic: false,
                usesCustomIcon: validCustomIconName(segment) != nil
            )

        case .dynamicProvider:
            return dynamicPlaceholder(
                segment: segment,
                pageID: page.id,
                slotIndex: segment.slotIndex,
                state: .loading,
                title: segment.customLabel ?? "Loading",
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    segment.customIcon?.systemSymbolName,
                    fallback: "clock"
                ),
                usesCustomIcon: validCustomIconName(segment) != nil
            )
        }
    }

    private func freezeCommand(
        reference: CommandReference,
        sourceSegment: CommandWheelSegment,
        pageID: UUID,
        slotIndex: Int,
        isDynamic: Bool,
        installedApplicationsByBundleID: [String: InstalledApplication],
        resolutionCache: inout CommandResolutionCache
    ) async throws -> CommandWheelPresentedSegment {
        do {
            let resolved = try await resolve(
                reference: reference,
                cache: &resolutionCache
            )
            let installedApplication = installedApplication(
                for: resolved.reference,
                in: installedApplicationsByBundleID
            )
            let customIconName = validCustomIconName(sourceSegment)
            let state: CommandWheelPresentedSegmentState
            switch resolved.availability {
            case .available:
                state = .available
            case .unavailable(let reason):
                state = .unavailable(reason)
            }
            return CommandWheelPresentedSegment(
                sourceSegmentID: sourceSegment.id,
                pageID: pageID,
                slotIndex: slotIndex,
                kind: .command(resolved.reference),
                state: state,
                title: normalized(sourceSegment.customLabel)
                    ?? installedApplication?.name
                    ?? resolved.manifest.title,
                subtitle: resolved.manifest.subtitle,
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    customIconName,
                    fallback: resolved.manifest.systemImage
                ),
                isDynamic: isDynamic,
                usesCustomIcon: customIconName != nil,
                applicationIconPath: customIconName == nil ? installedApplication?.path : nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommandRegistryError {
            let state: CommandWheelPresentedSegmentState
            if case .commandNotFound = error {
                state = .missing
            } else {
                state = .error
            }
            return unresolvedCommand(
                reference: reference,
                sourceSegment: sourceSegment,
                pageID: pageID,
                slotIndex: slotIndex,
                isDynamic: isDynamic,
                state: state,
                installedApplicationsByBundleID: installedApplicationsByBundleID
            )
        } catch {
            return unresolvedCommand(
                reference: reference,
                sourceSegment: sourceSegment,
                pageID: pageID,
                slotIndex: slotIndex,
                isDynamic: isDynamic,
                state: .error,
                installedApplicationsByBundleID: installedApplicationsByBundleID
            )
        }
    }

    private func unresolvedCommand(
        reference: CommandReference,
        sourceSegment: CommandWheelSegment,
        pageID: UUID,
        slotIndex: Int,
        isDynamic: Bool,
        state: CommandWheelPresentedSegmentState,
        installedApplicationsByBundleID: [String: InstalledApplication]
    ) -> CommandWheelPresentedSegment {
        let installedApplication = installedApplication(
            for: reference,
            in: installedApplicationsByBundleID
        )
        let customIconName = validCustomIconName(sourceSegment)
        return CommandWheelPresentedSegment(
            sourceSegmentID: sourceSegment.id,
            pageID: pageID,
            slotIndex: slotIndex,
            kind: .command(reference),
            state: state,
            title: normalized(sourceSegment.customLabel)
                ?? installedApplication?.name
                ?? reference.commandID.rawValue,
            subtitle: state == .missing ? "Command is no longer installed" : "Could not load command",
            systemImage: CommandWheelSystemSymbol.resolvedName(
                customIconName,
                fallback: state == .missing
                    ? "questionmark.circle" : "exclamationmark.triangle"
            ),
            isDynamic: isDynamic,
            usesCustomIcon: customIconName != nil,
            applicationIconPath: customIconName == nil ? installedApplication?.path : nil
        )
    }

    private func dynamicPlaceholder(
        segment: CommandWheelSegment,
        pageID: UUID,
        slotIndex: Int,
        state: CommandWheelPresentedSegmentState,
        title: String,
        systemImage: String,
        usesCustomIcon: Bool = false
    ) -> CommandWheelPresentedSegment {
        return CommandWheelPresentedSegment(
            sourceSegmentID: segment.id,
            pageID: pageID,
            slotIndex: slotIndex,
            kind: .empty,
            state: state,
            title: normalized(title) ?? "Dynamic commands",
            subtitle: nil,
            systemImage: CommandWheelSystemSymbol.resolvedName(systemImage, fallback: "clock"),
            isDynamic: true,
            usesCustomIcon: usesCustomIcon
        )
    }

    private func shouldInclude(
        _ segment: CommandWheelPresentedSegment,
        profile: CommandWheelProfile
    ) -> Bool {
        guard profile.hidesUnavailableSegments else { return true }
        switch segment.state {
        case .unavailable, .missing, .error:
            return false
        case .available, .loading, .empty:
            return true
        }
    }

    private func isReplayableDynamicCandidate(
        _ segment: CommandWheelPresentedSegment
    ) -> Bool {
        guard case .command = segment.kind else { return false }
        switch segment.state {
        case .available, .unavailable:
            return true
        case .loading, .empty, .missing, .error:
            return false
        }
    }

    private func orderedSummaries(
        _ summaries: [CommandUsageSummary],
        provider: CommandWheelDynamicProviderReference
    ) -> [CommandUsageSummary] {
        switch provider.sortingMethod {
        case .mostRecent:
            return summaries.sorted(by: Self.recentOrder)
        case .mostFrequent:
            return summaries.sorted(by: Self.frequentOrder)
        case .providerDefault:
            return provider.providerID == CommandWheelDynamicProviderID.recentCommands
                ? summaries.sorted(by: Self.recentOrder)
                : summaries.sorted(by: Self.frequentOrder)
        case .alphabetical:
            return summaries.sorted { $0.commandID.rawValue < $1.commandID.rawValue }
        }
    }

    private static func recentOrder(
        _ left: CommandUsageSummary,
        _ right: CommandUsageSummary
    ) -> Bool {
        if left.lastSuccessfulExecutionAt != right.lastSuccessfulExecutionAt {
            return left.lastSuccessfulExecutionAt > right.lastSuccessfulExecutionAt
        }
        if left.successfulExecutionCount != right.successfulExecutionCount {
            return left.successfulExecutionCount > right.successfulExecutionCount
        }
        return left.commandID.rawValue < right.commandID.rawValue
    }

    private static func frequentOrder(
        _ left: CommandUsageSummary,
        _ right: CommandUsageSummary
    ) -> Bool {
        if left.successfulExecutionCount != right.successfulExecutionCount {
            return left.successfulExecutionCount > right.successfulExecutionCount
        }
        return recentOrder(left, right)
    }

    private func clockwiseFreeSlots(
        startingAt startingSlot: Int,
        slotCount: Int,
        occupied: Set<Int>
    ) -> [Int] {
        guard slotCount > 0 else { return [] }
        let normalizedStart = ((startingSlot % slotCount) + slotCount) % slotCount
        return (0 ..< slotCount)
            .map { (normalizedStart + $0) % slotCount }
            .filter { occupied.contains($0) == false }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func validCustomIconName(_ segment: CommandWheelSegment) -> String? {
        guard let normalized = normalized(segment.customIcon?.systemSymbolName),
              CommandWheelSystemSymbol.isValid(normalized) else {
            return nil
        }
        return normalized
    }

    /// Reuses one resolution outcome for repeated references across pages/providers in this
    /// invocation. Failures are cached too, preventing a removed or malformed history entry from
    /// causing the same actor hop hundreds of times while preserving its visible state.
    private func resolve(
        reference: CommandReference,
        cache: inout CommandResolutionCache
    ) async throws -> ResolvedCommand {
        if let cached = cache.outcomes[reference] {
            switch cached {
            case .resolved(let command):
                return command
            case .registryError(let error):
                throw error
            case .failed:
                throw CachedCommandResolutionError.failed
            }
        }

        do {
            let resolved = try await resolver.resolve(reference: reference)
            cache.outcomes[reference] = .resolved(resolved)
            return resolved
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommandRegistryError {
            cache.outcomes[reference] = .registryError(error)
            throw error
        } catch {
            cache.outcomes[reference] = .failed
            throw CachedCommandResolutionError.failed
        }
    }

    private func installedApplication(
        for reference: CommandReference,
        in applicationsByBundleID: [String: InstalledApplication]
    ) -> InstalledApplication? {
        guard let bundleIdentifier = installedApplicationBundleIdentifier(reference) else {
            return nil
        }
        return applicationsByBundleID[normalizedBundleIdentifier(bundleIdentifier)]
    }

    private func installedApplicationBundleIdentifier(
        _ reference: CommandReference
    ) -> String? {
        guard reference.commandID == BuiltInCommandID.openInstalledApplication,
              case .string(let bundleIdentifier)? = reference.arguments[
                  BuiltInCommandArgumentName.bundleIdentifier
              ] else {
            return nil
        }
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct DynamicCandidate {
        let summary: CommandUsageSummary
        let segment: CommandWheelPresentedSegment
    }

    private struct CommandResolutionCache {
        var outcomes: [CommandReference: CachedCommandResolution] = [:]
    }

    private enum CachedCommandResolution {
        case resolved(ResolvedCommand)
        case registryError(CommandRegistryError)
        case failed
    }

    private enum CachedCommandResolutionError: Error {
        case failed
    }
}
