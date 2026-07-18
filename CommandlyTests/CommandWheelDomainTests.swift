import CommandKit
import Foundation
import Testing
@testable import Commandly

@Suite("Command Wheel domain")
struct CommandWheelDomainTests {
    private let validator = CommandWheelConfigurationValidator()

    @Test
    func defaultsUseOnlyRegisteredCommandsAndValidate() throws {
        let configuration = CommandWheelDefaults.configuration

        try validator.validate(configuration)

        let profile = try #require(configuration.profiles.first)
        let page = try #require(profile.pages.first)
        let commandIDs: Set<CommandID> = Set(page.segments.compactMap { segment in
            guard case .command(let reference) = segment.content else { return nil }
            return reference.commandID
        })

        #expect(configuration.isEnabled == false)
        #expect(profile.isEnabled)
        #expect(profile.shortcut == nil)
        #expect(profile.interaction.visibleSlotCount == 8)
        #expect(page.segments.count == 8)
        #expect(commandIDs == [
            BuiltInCommandID.searchFiles,
            BuiltInCommandID.clipboardHistory,
            BuiltInCommandID.openSettings,
        ])
    }

    @Test
    func configurationRoundTripsThroughStableCodableRepresentations() throws {
        var configuration = CommandWheelDefaults.configuration
        configuration.profiles[0].placement = .fixedNormalizedPoint(
            screenIdentifier: "display-primary",
            x: 0.25,
            y: 0.75
        )
        configuration.profiles[0].pages[0].segments[1].content = .dynamicProvider(
            CommandWheelDynamicProviderReference(
                providerID: CommandWheelDynamicProviderID.recentCommands,
                maximumResultCount: 3,
                sortingMethod: .mostRecent,
                emptyState: .showEmptySlots,
                refreshStrategy: .onInvocation,
                cachePolicy: .invocation
            )
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(
            CommandWheelConfiguration.self,
            from: data
        )

        #expect(decoded == configuration)
        try validator.validate(decoded)
    }

    @Test
    func rejectsDuplicateProfilePageSegmentAndContextRuleIDs() throws {
        let baseline = CommandWheelDefaults.configuration

        var duplicateProfile = baseline
        duplicateProfile.profiles.append(baseline.profiles[0])
        #expect(throws: CommandWheelValidationError.duplicateProfileID(
            baseline.profiles[0].id
        )) {
            try validator.validate(duplicateProfile)
        }

        var duplicatePage = baseline
        duplicatePage.profiles[0].pages.append(baseline.profiles[0].pages[0])
        #expect(throws: CommandWheelValidationError.duplicatePageID(
            baseline.profiles[0].pages[0].id
        )) {
            try validator.validate(duplicatePage)
        }

        var duplicateSegment = baseline
        let firstSegment = baseline.profiles[0].pages[0].segments[0]
        duplicateSegment.profiles[0].pages[0].segments = [
            firstSegment,
            CommandWheelSegment(
                id: firstSegment.id,
                slotIndex: 1,
                content: .empty,
                customLabel: nil,
                customIcon: nil
            ),
        ]
        #expect(throws: CommandWheelValidationError.duplicateSegmentID(firstSegment.id)) {
            try validator.validate(duplicateSegment)
        }

        var duplicateRule = baseline
        let ruleID = commandWheelTestID(70)
        duplicateRule.profiles[0].contextRules = [
            CommandWheelContextRule(
                id: ruleID,
                frontmostApplicationBundleIdentifier: "com.example.one",
                priority: 1,
                isEnabled: true
            ),
            CommandWheelContextRule(
                id: ruleID,
                frontmostApplicationBundleIdentifier: "com.example.two",
                priority: 2,
                isEnabled: true
            ),
        ]
        #expect(throws: CommandWheelValidationError.duplicateContextRuleID(ruleID)) {
            try validator.validate(duplicateRule)
        }
    }

    @Test
    func rejectsDuplicateAndOutOfRangeSlots() throws {
        var duplicate = CommandWheelDefaults.configuration
        duplicate.profiles[0].pages[0].segments[1].slotIndex = 0
        let pageID = duplicate.profiles[0].pages[0].id
        #expect(throws: CommandWheelValidationError.duplicateSlot(
            pageID: pageID,
            slotIndex: 0
        )) {
            try validator.validate(duplicate)
        }

        var outsideRange = CommandWheelDefaults.configuration
        outsideRange.profiles[0].pages[0].segments[0].slotIndex = 8
        #expect(throws: CommandWheelValidationError.invalidSlot(
            pageID: pageID,
            slotIndex: 8
        )) {
            try validator.validate(outsideRange)
        }
    }

    @Test
    func rejectsMissingCyclicAndUnreachableSubmenuPages() throws {
        let rootID = commandWheelTestID(80)
        let childID = commandWheelTestID(81)
        let profileID = commandWheelTestID(82)
        let missingID = commandWheelTestID(83)

        var missing = makeConfiguration(
            profile: makeProfile(
                id: profileID,
                rootPageID: rootID,
                pages: [
                    CommandWheelPage(
                        id: rootID,
                        name: "Root",
                        segments: [submenuSegment(id: commandWheelTestID(84), pageID: missingID)]
                    ),
                ]
            )
        )
        #expect(throws: CommandWheelValidationError.missingSubmenuPage(
            segmentID: commandWheelTestID(84)
        )) {
            try validator.validate(missing)
        }

        missing.profiles[0].pages.append(
            CommandWheelPage(id: childID, name: "Child", segments: [])
        )
        missing.profiles[0].pages[0].segments[0].content = .submenu(pageID: childID)
        missing.profiles[0].pages[1].segments = [
            submenuSegment(id: commandWheelTestID(85), pageID: rootID),
        ]
        #expect(throws: CommandWheelValidationError.submenuCycle(rootID)) {
            try validator.validate(missing)
        }

        let unreachable = makeConfiguration(
            profile: makeProfile(
                id: profileID,
                rootPageID: rootID,
                pages: [
                    CommandWheelPage(id: rootID, name: "Root", segments: []),
                    CommandWheelPage(id: childID, name: "Child", segments: []),
                ]
            )
        )
        #expect(throws: CommandWheelValidationError.unreachablePage(childID)) {
            try validator.validate(unreachable)
        }
    }

    @Test
    func rejectsUnsupportedProvidersInvalidRangesAndMalformedCommands() throws {
        var provider = CommandWheelDefaults.configuration
        let segmentID = provider.profiles[0].pages[0].segments[0].id
        provider.profiles[0].pages[0].segments[0].content = .dynamicProvider(
            CommandWheelDynamicProviderReference(
                providerID: "unsupported.private-provider",
                maximumResultCount: 1,
                sortingMethod: .providerDefault,
                emptyState: .showEmptySlots,
                refreshStrategy: .onInvocation,
                cachePolicy: .invocation
            )
        )
        #expect(throws: CommandWheelValidationError.unsupportedDynamicProvider(segmentID)) {
            try validator.validate(provider)
        }

        for refreshStrategy in [
            CommandWheelDynamicProviderRefreshStrategy.onProfileChange,
            .manual,
        ] {
            var unsupportedRefresh = CommandWheelDefaults.configuration
            unsupportedRefresh.profiles[0].pages[0].segments[0].content = .dynamicProvider(
                CommandWheelDynamicProviderReference(
                    providerID: CommandWheelDynamicProviderID.recentCommands,
                    maximumResultCount: 1,
                    sortingMethod: .mostRecent,
                    emptyState: .showEmptySlots,
                    refreshStrategy: refreshStrategy,
                    cachePolicy: .invocation
                )
            )
            #expect(throws: CommandWheelValidationError.invalidDynamicProviderConfiguration(
                segmentID
            )) {
                try validator.validate(unsupportedRefresh)
            }
        }

        var unsupportedCache = CommandWheelDefaults.configuration
        unsupportedCache.profiles[0].pages[0].segments[0].content = .dynamicProvider(
            CommandWheelDynamicProviderReference(
                providerID: CommandWheelDynamicProviderID.frequentCommands,
                maximumResultCount: 1,
                sortingMethod: .mostFrequent,
                emptyState: .showEmptySlots,
                refreshStrategy: .onInvocation,
                cachePolicy: .session
            )
        )
        #expect(throws: CommandWheelValidationError.invalidDynamicProviderConfiguration(
            segmentID
        )) {
            try validator.validate(unsupportedCache)
        }

        var appearance = CommandWheelDefaults.configuration
        let profileID = appearance.profiles[0].id
        appearance.profiles[0].appearance.wheelRadius = .infinity
        #expect(throws: CommandWheelValidationError.invalidAppearance(profileID)) {
            try validator.validate(appearance)
        }

        var command = CommandWheelDefaults.configuration
        command.profiles[0].pages[0].segments[0].content = .command(
            CommandReference(
                commandID: CommandID(rawValue: "   "),
                arguments: CommandArguments(["value": .decimal(.nan)])
            )
        )
        #expect(throws: CommandWheelValidationError.invalidCommandReference(segmentID)) {
            try validator.validate(command)
        }
    }

    @Test
    func validatesCustomIconsAgainstNativeSFSymbolCatalog() throws {
        #expect(CommandWheelSystemSymbol.isValid(CommandWheelSystemSymbol.guaranteedFallback))
        var valid = CommandWheelDefaults.configuration
        valid.profiles[0].pages[0].segments[0].customIcon = CommandWheelIconOverride(
            systemSymbolName: "star.fill"
        )
        try validator.validate(valid)

        var invalid = CommandWheelDefaults.configuration
        let segmentID = invalid.profiles[0].pages[0].segments[0].id
        invalid.profiles[0].pages[0].segments[0].customIcon = CommandWheelIconOverride(
            systemSymbolName: "commandly.symbol.that.does.not.exist"
        )
        #expect(throws: CommandWheelValidationError.invalidCustomIcon(segmentID)) {
            try validator.validate(invalid)
        }

        #expect(
            CommandWheelSystemSymbol.resolvedName(
                "commandly.symbol.that.does.not.exist",
                fallback: "star"
            ) == "star"
        )
    }

    @Test
    func contextResolutionUsesExplicitContextAndDefaultPriorityDeterministically() throws {
        let first = makeProfile(
            id: commandWheelTestID(90),
            rootPageID: commandWheelTestID(91),
            pages: [
                CommandWheelPage(
                    id: commandWheelTestID(91),
                    name: "First",
                    segments: []
                ),
            ],
            rules: [
                CommandWheelContextRule(
                    id: commandWheelTestID(92),
                    frontmostApplicationBundleIdentifier: "com.example.editor",
                    priority: 10,
                    isEnabled: true
                ),
            ]
        )
        let second = makeProfile(
            id: commandWheelTestID(93),
            rootPageID: commandWheelTestID(94),
            pages: [
                CommandWheelPage(
                    id: commandWheelTestID(94),
                    name: "Second",
                    segments: []
                ),
            ],
            rules: [
                CommandWheelContextRule(
                    id: commandWheelTestID(95),
                    frontmostApplicationBundleIdentifier: "COM.EXAMPLE.EDITOR",
                    priority: 20,
                    isEnabled: true
                ),
            ]
        )
        let configuration = CommandWheelConfiguration(
            isEnabled: true,
            contextAwareProfileSelectionEnabled: true,
            defaultProfileID: first.id,
            profiles: [first, second]
        )
        try validator.validate(configuration)

        #expect(CommandWheelProfileSelector.resolve(
            configuration: configuration,
            explicitProfileID: first.id,
            frontmostApplicationBundleIdentifier: "com.example.editor"
        ) == CommandWheelProfileSelection(profileID: first.id, reason: .explicit))

        #expect(CommandWheelProfileSelector.resolve(
            configuration: configuration,
            explicitProfileID: first.id,
            allowsContextOverride: true,
            frontmostApplicationBundleIdentifier: " com.example.editor "
        ) == CommandWheelProfileSelection(
            profileID: second.id,
            reason: .context(ruleID: commandWheelTestID(95))
        ))

        #expect(CommandWheelProfileSelector.resolve(
            configuration: configuration,
            frontmostApplicationBundleIdentifier: "com.example.unmatched"
        ) == CommandWheelProfileSelection(
            profileID: first.id,
            reason: .defaultProfile
        ))
    }

    @Test
    func contextValidationRejectsAmbiguousEqualPriorityMatches() {
        let ruleID = commandWheelTestID(100)
        var configuration = CommandWheelDefaults.configuration
        configuration.profiles[0].contextRules = [
            CommandWheelContextRule(
                id: ruleID,
                frontmostApplicationBundleIdentifier: "com.example.editor",
                priority: 5,
                isEnabled: true
            ),
            CommandWheelContextRule(
                id: commandWheelTestID(101),
                frontmostApplicationBundleIdentifier: "COM.EXAMPLE.EDITOR",
                priority: 5,
                isEnabled: true
            ),
        ]

        #expect(throws: CommandWheelValidationError.conflictingContextRules(priority: 5)) {
            try validator.validate(configuration)
        }
    }
}

private func makeConfiguration(profile: CommandWheelProfile) -> CommandWheelConfiguration {
    CommandWheelConfiguration(
        isEnabled: true,
        contextAwareProfileSelectionEnabled: false,
        defaultProfileID: profile.id,
        profiles: [profile]
    )
}

private func makeProfile(
    id: UUID,
    rootPageID: UUID,
    pages: [CommandWheelPage],
    rules: [CommandWheelContextRule] = []
) -> CommandWheelProfile {
    CommandWheelProfile(
        id: id,
        name: "Profile",
        isEnabled: true,
        shortcut: nil,
        activationBehavior: .holdAndRelease,
        placement: .cursor,
        rootPageID: rootPageID,
        pages: pages,
        contextRules: rules,
        appearance: CommandWheelDefaults.appearance,
        interaction: CommandWheelDefaults.interaction,
        hidesUnavailableSegments: false
    )
}

private func submenuSegment(id: UUID, pageID: UUID) -> CommandWheelSegment {
    CommandWheelSegment(
        id: id,
        slotIndex: 0,
        content: .submenu(pageID: pageID),
        customLabel: nil,
        customIcon: nil
    )
}

private nonisolated func commandWheelTestID(_ finalByte: UInt8) -> UUID {
    UUID(uuid: (
        0x54, 0x45, 0x53, 0x54,
        0x43, 0x4D,
        0x44, 0x57,
        0x80, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, finalByte
    ))
}
