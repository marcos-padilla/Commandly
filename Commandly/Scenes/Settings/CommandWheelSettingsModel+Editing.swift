import AppCore
import CommandKit
import Foundation

@MainActor
extension CommandWheelSettingsModel {
    func renamePage(_ pageID: UUID, to requestedName: String) async throws {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { throw CommandWheelSettingsError.invalidName }
        guard let profileID = selectedProfileID else {
            throw CommandWheelSettingsError.profileNotFound
        }
        try await updateProfile(profileID) { profile in
            guard let index = profile.pages.firstIndex(where: { $0.id == pageID }) else {
                throw CommandWheelSettingsError.pageNotFound
            }
            profile.pages[index].name = String(
                name.prefix(CommandWheelLimits.maximumNameLength)
            )
        }
        statusMessage = "Renamed wheel page."
    }

    func addPage(
        named requestedName: String,
        from slotIndex: Int,
        replacing: Bool = false
    ) async throws {
        guard let profileID = selectedProfileID, let pageID = selectedPageID else {
            throw CommandWheelSettingsError.pageNotFound
        }
        let newPageID = try await store.createSubmenu(
            named: requestedName,
            at: CommandWheelSlotLocation(
                profileID: profileID,
                pageID: pageID,
                slotIndex: slotIndex
            ),
            replacing: replacing
        )
        selectedPageID = newPageID
        selectedSlotIndex = nil
        statusMessage = "Added submenu page."
    }

    func deletePage(_ pageID: UUID) async throws {
        guard let profile = selectedProfile else {
            throw CommandWheelSettingsError.profileNotFound
        }
        guard pageID != profile.rootPageID else {
            throw CommandWheelSettingsError.cannotDeleteRootPage
        }
        guard profile.pages.contains(where: { $0.id == pageID }) else {
            throw CommandWheelSettingsError.pageNotFound
        }

        let removedIDs = submenuTree(rootedAt: pageID, in: profile)
        try await updateProfile(profile.id) { profile in
            for parentIndex in profile.pages.indices {
                for segmentIndex in profile.pages[parentIndex].segments.indices {
                    if case .submenu(let childID) = profile.pages[parentIndex]
                        .segments[segmentIndex].content,
                       removedIDs.contains(childID) {
                        profile.pages[parentIndex].segments[segmentIndex].content = .empty
                        profile.pages[parentIndex].segments[segmentIndex].customLabel = nil
                        profile.pages[parentIndex].segments[segmentIndex].customIcon = nil
                    }
                }
            }
            profile.pages.removeAll { removedIDs.contains($0.id) }
        }
        selectedPageID = profile.rootPageID
        selectedSlotIndex = nil
        statusMessage = "Deleted submenu page."
    }

    func setActivationBehavior(
        _ behavior: CommandWheelActivationBehavior,
        profileID: UUID
    ) async throws {
        try await updateProfile(profileID) { $0.activationBehavior = behavior }
    }

    func setPlacement(_ placement: CommandWheelPlacement, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.placement = placement }
    }

    func setFixedPlacementCoordinates(
        x: Double,
        y: Double,
        profileID: UUID
    ) async throws {
        try await updateProfile(profileID) { profile in
            let screenIdentifier: String?
            if case .fixedNormalizedPoint(let existingIdentifier, _, _) = profile.placement {
                screenIdentifier = existingIdentifier
            } else {
                screenIdentifier = nil
            }
            profile.placement = .fixedNormalizedPoint(
                screenIdentifier: screenIdentifier,
                x: x,
                y: y
            )
        }
    }

    func setFixedPlacementScreenIdentifier(
        _ screenIdentifier: String?,
        profileID: UUID
    ) async throws {
        try await updateProfile(profileID) { profile in
            let x: Double
            let y: Double
            if case .fixedNormalizedPoint(_, let existingX, let existingY) = profile.placement {
                x = existingX
                y = existingY
            } else {
                x = 0.5
                y = 0.5
            }
            profile.placement = .fixedNormalizedPoint(
                screenIdentifier: screenIdentifier,
                x: x,
                y: y
            )
        }
    }

    func setWheelRadius(_ radius: Double, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.appearance.wheelRadius = radius }
    }

    func setDeadZoneRadius(_ radius: Double, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.interaction.deadZoneRadius = radius }
    }

    func setSlotCount(_ count: Int, profileID: UUID) async throws {
        try ensureSlotsCanBeRemoved(visibleSlotCount: count, profileID: profileID)
        try await store.setVisibleSlotCount(count, profileID: profileID)
        repairSelection()
    }

    func resetInteractionDefaults(profileID: UUID) async throws {
        try ensureSlotsCanBeRemoved(
            visibleSlotCount: CommandWheelDefaults.interaction.visibleSlotCount,
            profileID: profileID
        )
        try await store.setInteractionConfiguration(
            CommandWheelDefaults.interaction,
            profileID: profileID
        )
        repairSelection()
        statusMessage = "Reset interaction settings to defaults."
    }

    func setClickSelectionEnabled(_ enabled: Bool, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.interaction.allowsClickSelection = enabled }
    }

    func setKeyboardSelectionEnabled(_ enabled: Bool, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.interaction.allowsKeyboardSelection = enabled }
    }

    func setSubmenuBehavior(
        _ behavior: CommandWheelSubmenuActivationBehavior,
        profileID: UUID
    ) async throws {
        try await updateProfile(profileID) { profile in
            profile.interaction.submenuActivationBehavior = behavior
            if behavior == .dwell,
               profile.interaction.submenuDwellDurationSeconds == 0 {
                profile.interaction.submenuDwellDurationSeconds =
                    CommandWheelDefaults.interaction.submenuDwellDurationSeconds
            }
            if behavior == .clickOnly {
                profile.interaction.allowsClickSelection = true
            }
        }
    }

    func setSubmenuDwellDuration(_ duration: Double, profileID: UUID) async throws {
        try await updateProfile(profileID) {
            $0.interaction.submenuDwellDurationSeconds = duration
        }
    }

    func setAnimationPreference(
        _ preference: CommandWheelAnimationPreference,
        profileID: UUID
    ) async throws {
        try await updateProfile(profileID) { $0.appearance.animationPreference = preference }
    }

    func setKeyboardHintsVisible(_ visible: Bool, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.appearance.showsKeyboardHints = visible }
    }

    func setUnavailableSegmentsHidden(_ hidden: Bool, profileID: UUID) async throws {
        try await updateProfile(profileID) { $0.hidesUnavailableSegments = hidden }
    }

    func resetProfile(_ profileID: UUID) async throws {
        guard let source = profiles.first(where: { $0.id == profileID }) else {
            throw CommandWheelSettingsError.profileNotFound
        }
        var usedIDs = Set(profiles.map(\.id))
            .union(profiles.flatMap(\.pages).map(\.id))
            .union(profiles.flatMap(\.pages).flatMap(\.segments).map(\.id))
            .union(profiles.flatMap(\.contextRules).map(\.id))
        let rootPageID = try editorNextID(used: &usedIDs)
        var segments: [CommandWheelSegment] = []
        for defaultSegment in CommandWheelDefaults.defaultProfile.pages[0].segments {
            segments.append(
                CommandWheelSegment(
                    id: try editorNextID(used: &usedIDs),
                    slotIndex: defaultSegment.slotIndex,
                    content: defaultSegment.content,
                    customLabel: nil,
                    customIcon: nil
                )
            )
        }
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            configuration.profiles[index] = CommandWheelProfile(
                id: source.id,
                name: source.name,
                isEnabled: source.isEnabled,
                shortcut: nil,
                activationBehavior: .holdAndRelease,
                placement: .cursor,
                rootPageID: rootPageID,
                pages: [CommandWheelPage(id: rootPageID, name: "Main", segments: segments)],
                contextRules: [],
                appearance: CommandWheelDefaults.appearance,
                interaction: CommandWheelDefaults.interaction,
                hidesUnavailableSegments: false
            )
        }
        selectedProfileID = profileID
        selectedPageID = rootPageID
        selectedSlotIndex = nil
        statusMessage = "Reset \(source.name) to defaults."
    }

    func assignCommand(
        _ commandID: CommandID,
        to slotIndex: Int,
        replacing: Bool
    ) async throws {
        guard commandPicker.assignableManifest(for: commandID) != nil else {
            throw CommandWheelSettingsError.commandNotFound
        }
        try await assignCommand(
            CommandReference(commandID: commandID),
            customLabel: nil,
            to: slotIndex,
            replacing: replacing
        )
    }

    private func assignCommand(
        _ reference: CommandReference,
        customLabel: String?,
        to slotIndex: Int,
        replacing: Bool
    ) async throws {
        guard commandPicker.isValidAssignment(reference) else {
            throw CommandWheelSettingsError.invalidArgumentValue
        }
        let location = try selectedLocation(slotIndex: slotIndex)
        try await store.assign(
            reference,
            to: location,
            replacing: replacing,
            customLabel: customLabel
        )
        selectedSlotIndex = slotIndex
        pendingReplacement = nil
        statusMessage = "Assigned command to slot \(slotIndex + 1)."
    }

    func requestCommandAssignment(_ commandID: CommandID, to slotIndex: Int) async throws {
        guard let manifest = commandPicker.assignableManifest(for: commandID) else {
            throw CommandWheelSettingsError.commandNotFound
        }
        try await requestCommandAssignment(
            reference: CommandReference(commandID: commandID),
            title: manifest.title,
            customLabel: nil,
            to: slotIndex
        )
    }

    func requestCommandAssignment(
        _ option: CommandWheelCommandOption,
        to slotIndex: Int
    ) async throws {
        let customLabel = option.reference.commandID
            == BuiltInCommandID.openInstalledApplication ? option.title : nil
        try await requestCommandAssignment(
            reference: option.reference,
            title: option.title,
            customLabel: customLabel,
            to: slotIndex
        )
    }

    private func requestCommandAssignment(
        reference: CommandReference,
        title: String,
        customLabel: String?,
        to slotIndex: Int
    ) async throws {
        guard commandPicker.isValidAssignment(reference) else {
            throw CommandWheelSettingsError.invalidArgumentValue
        }
        let destination = try selectedLocation(slotIndex: slotIndex)
        if store.occupiedSlot(
            profileID: destination.profileID,
            pageID: destination.pageID,
            slotIndex: destination.slotIndex
        ) != nil {
            pendingReplacement = CommandWheelPendingReplacement(
                reference: reference,
                destination: destination,
                title: title,
                customLabel: customLabel
            )
            return
        }
        try await assignCommand(
            reference,
            customLabel: customLabel,
            to: slotIndex,
            replacing: false
        )
    }

    func confirmPendingReplacement() async throws {
        guard let pendingReplacement else { return }
        try await store.assign(
            pendingReplacement.reference,
            to: pendingReplacement.destination,
            replacing: true,
            customLabel: pendingReplacement.customLabel
        )
        selectedSlotIndex = pendingReplacement.destination.slotIndex
        self.pendingReplacement = nil
        statusMessage = "Replaced the occupied wheel slot."
    }

    func cancelPendingReplacement() {
        pendingReplacement = nil
    }

    func assignDynamicProvider(
        _ providerID: String,
        to slotIndex: Int,
        replacing: Bool
    ) async throws {
        guard CommandWheelDynamicProviderID.supported.contains(providerID) else {
            throw CommandWheelSettingsError.commandNotFound
        }
        let location = try selectedLocation(slotIndex: slotIndex)
        let sorting: CommandWheelDynamicProviderSortingMethod =
            providerID == CommandWheelDynamicProviderID.recentCommands
                ? .mostRecent : .mostFrequent
        let reference = CommandWheelDynamicProviderReference(
            providerID: providerID,
            maximumResultCount: min(4, selectedProfile?.interaction.visibleSlotCount ?? 1),
            sortingMethod: sorting,
            emptyState: .showEmptySlots,
            refreshStrategy: .onInvocation,
            cachePolicy: .invocation
        )
        try await store.assignContent(
            .dynamicProvider(reference),
            to: location,
            replacing: replacing
        )
        selectedSlotIndex = slotIndex
    }

    func clearSlot(_ slotIndex: Int) async throws {
        try await store.remove(at: selectedLocation(slotIndex: slotIndex))
        selectedSlotIndex = slotIndex
        statusMessage = "Cleared wheel slot \(slotIndex + 1)."
    }

    func moveSlot(
        _ slotIndex: Int,
        direction: CommandWheelMoveDirection,
        replacing: Bool = true
    ) async throws {
        guard let profile = selectedProfile else {
            throw CommandWheelSettingsError.profileNotFound
        }
        let destinationIndex = direction == .earlier ? slotIndex - 1 : slotIndex + 1
        guard (0 ..< profile.interaction.visibleSlotCount).contains(destinationIndex) else {
            return
        }
        let source = try selectedLocation(slotIndex: slotIndex)
        let destination = try selectedLocation(slotIndex: destinationIndex)
        if replacing {
            try await store.swap(source, destination)
        } else {
            try await store.move(from: source, to: destination, replacing: false)
        }
        selectedSlotIndex = destinationIndex
    }

    func setSegmentLabel(_ label: String?, slotIndex: Int) async throws {
        let location = try selectedLocation(slotIndex: slotIndex)
        try await updateSegment(at: location) { segment in
            let normalized = label?.trimmingCharacters(in: .whitespacesAndNewlines)
            segment.customLabel = normalized?.isEmpty == true ? nil : normalized
        }
    }

    func setSegmentIcon(_ systemSymbol: String?, slotIndex: Int) async throws {
        let normalized = systemSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, normalized.isEmpty == false,
           CommandWheelSystemSymbol.isValid(normalized) == false {
            throw CommandWheelSettingsError.invalidSymbol
        }
        let location = try selectedLocation(slotIndex: slotIndex)
        try await updateSegment(at: location) { segment in
            segment.customIcon = normalized?.isEmpty == false
                ? CommandWheelIconOverride(systemSymbolName: normalized ?? "") : nil
        }
    }

    /// Applies label and SF Symbol changes as one validated store transaction. An invalid symbol
    /// leaves both existing presentation values untouched.
    func setSegmentPresentation(
        label: String?,
        systemSymbol: String?,
        slotIndex: Int
    ) async throws {
        let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedLabel,
           normalizedLabel.isEmpty == false,
           normalizedLabel.count > CommandWheelLimits.maximumNameLength {
            throw CommandWheelSettingsError.invalidName
        }
        let normalizedSymbol = systemSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedSymbol, normalizedSymbol.isEmpty == false,
           CommandWheelSystemSymbol.isValid(normalizedSymbol) == false {
            throw CommandWheelSettingsError.invalidSymbol
        }

        let location = try selectedLocation(slotIndex: slotIndex)
        try await updateSegment(at: location) { segment in
            segment.customLabel = normalizedLabel?.isEmpty == false ? normalizedLabel : nil
            segment.customIcon = normalizedSymbol?.isEmpty == false
                ? CommandWheelIconOverride(systemSymbolName: normalizedSymbol ?? "") : nil
        }
    }

    func setArgumentValue(
        _ value: CommandArgumentValue?,
        argument: CommandArgument,
        slotIndex: Int
    ) async throws {
        if let value, value.valueType != argument.valueType {
            throw CommandWheelSettingsError.invalidArgumentValue
        }
        if value == nil, argument.isRequired, argument.defaultValue == nil {
            throw CommandWheelSettingsError.requiredArgumentMissing
        }
        let location = try selectedLocation(slotIndex: slotIndex)
        try await store.update { configuration in
            try Self.updateCommandReference(
                at: location,
                configuration: &configuration
            ) { reference in
                guard commandPicker.manifest(for: reference.commandID)?.arguments.contains(
                    where: { $0.name == argument.name && $0.valueType == argument.valueType }
                ) == true else {
                    throw CommandWheelSettingsError.commandNotFound
                }
                var values = reference.arguments.values
                values[argument.name] = value
                return CommandReference(
                    commandID: reference.commandID,
                    arguments: CommandArguments(values)
                )
            }
        }
    }

    func setArgumentText(
        _ text: String,
        argument: CommandArgument,
        slotIndex: Int
    ) async throws {
        let value: CommandArgumentValue?
        if text.isEmpty, argument.isRequired == false {
            value = nil
        } else {
            switch argument.valueType {
            case .string:
                value = .string(text)
            case .boolean:
                guard let boolean = Bool(text.lowercased()) else {
                    throw CommandWheelSettingsError.invalidArgumentValue
                }
                value = .boolean(boolean)
            case .integer:
                guard let integer = Int(text) else {
                    throw CommandWheelSettingsError.invalidArgumentValue
                }
                value = .integer(integer)
            case .decimal:
                guard let decimal = Double(text), decimal.isFinite else {
                    throw CommandWheelSettingsError.invalidArgumentValue
                }
                value = .decimal(decimal)
            case .url:
                guard let url = URL(string: text), url.absoluteString.isEmpty == false else {
                    throw CommandWheelSettingsError.invalidArgumentValue
                }
                value = .url(url)
            case .stringList:
                value = .stringList(
                    text.split(whereSeparator: \.isNewline).map(String.init)
                )
            }
        }
        try await setArgumentValue(value, argument: argument, slotIndex: slotIndex)
    }

    func argumentValue(_ argument: CommandArgument, slotIndex: Int) -> CommandArgumentValue? {
        guard let segment = selectedPage?.segments.first(where: {
            $0.slotIndex == slotIndex
        }), case .command(let reference) = segment.content else {
            return nil
        }
        return reference.arguments[argument.name] ?? argument.defaultValue
    }

    func addContextRule(bundleIdentifier: String, priority: Int) async throws {
        guard let profileID = selectedProfileID else {
            throw CommandWheelSettingsError.profileNotFound
        }
        if contextConflictMessage(
            bundleIdentifier: bundleIdentifier,
            priority: priority
        ) != nil {
            throw CommandWheelSettingsError.contextRuleConflict
        }
        var usedIDs = Set(profiles.flatMap(\.contextRules).map(\.id))
        let ruleID = try editorNextID(used: &usedIDs)
        try await updateProfile(profileID) { profile in
            profile.contextRules.append(
                CommandWheelContextRule(
                    id: ruleID,
                    frontmostApplicationBundleIdentifier: bundleIdentifier,
                    priority: priority,
                    isEnabled: true
                )
            )
        }
    }

    func updateContextRule(
        _ ruleID: UUID,
        bundleIdentifier: String,
        priority: Int,
        isEnabled: Bool
    ) async throws {
        guard let profileID = selectedProfileID else {
            throw CommandWheelSettingsError.profileNotFound
        }
        if isEnabled,
           contextConflictMessage(
               bundleIdentifier: bundleIdentifier,
               priority: priority,
               excluding: ruleID
           ) != nil {
            throw CommandWheelSettingsError.contextRuleConflict
        }
        try await updateProfile(profileID) { profile in
            guard let index = profile.contextRules.firstIndex(where: { $0.id == ruleID }) else {
                throw CommandWheelSettingsError.pageNotFound
            }
            profile.contextRules[index].frontmostApplicationBundleIdentifier = bundleIdentifier
            profile.contextRules[index].priority = priority
            profile.contextRules[index].isEnabled = isEnabled
        }
    }

    func deleteContextRule(_ ruleID: UUID) async throws {
        guard let profileID = selectedProfileID else {
            throw CommandWheelSettingsError.profileNotFound
        }
        try await updateProfile(profileID) { profile in
            profile.contextRules.removeAll { $0.id == ruleID }
        }
    }

    func exportProfiles(_ profileIDs: Set<UUID>? = nil) async throws -> Data {
        try await store.exportProfiles(ids: profileIDs)
    }

    func importProfiles(from data: Data) async throws {
        let result = try await store.importProfiles(
            from: data,
            knownCommandIDs: catalog.knownCommandIDs
        )
        setImportFeedback(result)
    }

    private func selectedLocation(slotIndex: Int) throws -> CommandWheelSlotLocation {
        guard let profileID = selectedProfileID else {
            throw CommandWheelSettingsError.profileNotFound
        }
        guard let pageID = selectedPageID else {
            throw CommandWheelSettingsError.pageNotFound
        }
        return CommandWheelSlotLocation(
            profileID: profileID,
            pageID: pageID,
            slotIndex: slotIndex
        )
    }

    private func ensureSlotsCanBeRemoved(
        visibleSlotCount count: Int,
        profileID: UUID
    ) throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            throw CommandWheelSettingsError.profileNotFound
        }
        if count < profile.interaction.visibleSlotCount,
           profile.pages.contains(where: { page in
               page.segments.contains { segment in
                   segment.slotIndex >= count && segment.content != .empty
               }
           }) {
            throw CommandWheelSettingsError.occupiedSlotsOutsideRange
        }
    }

    private func submenuTree(
        rootedAt pageID: UUID,
        in profile: CommandWheelProfile
    ) -> Set<UUID> {
        var result: Set<UUID> = []
        func collect(_ currentID: UUID) {
            guard result.insert(currentID).inserted,
                  let page = profile.pages.first(where: { $0.id == currentID }) else {
                return
            }
            for segment in page.segments {
                if case .submenu(let childID) = segment.content { collect(childID) }
            }
        }
        collect(pageID)
        return result
    }

    private func editorNextID(used: inout Set<UUID>) throws -> UUID {
        for _ in 0 ..< 256 {
            let candidate = uuidProvider.uuid()
            if used.insert(candidate).inserted { return candidate }
        }
        throw CommandWheelSettingsError.identifierGenerationFailed
    }

    private func updateSegment(
        at location: CommandWheelSlotLocation,
        edit: (inout CommandWheelSegment) throws -> Void
    ) async throws {
        try await store.update { configuration in
            guard let profileIndex = configuration.profiles.firstIndex(where: {
                $0.id == location.profileID
            }), let pageIndex = configuration.profiles[profileIndex].pages.firstIndex(where: {
                $0.id == location.pageID
            }), let segmentIndex = configuration.profiles[profileIndex].pages[pageIndex]
                .segments.firstIndex(where: { $0.slotIndex == location.slotIndex }) else {
                throw CommandWheelProfileEditError.segmentNotFound
            }
            try edit(
                &configuration.profiles[profileIndex].pages[pageIndex].segments[segmentIndex]
            )
        }
    }

    private nonisolated static func updateCommandReference(
        at location: CommandWheelSlotLocation,
        configuration: inout CommandWheelConfiguration,
        update: (CommandReference) throws -> CommandReference
    ) throws {
        guard let profileIndex = configuration.profiles.firstIndex(where: {
            $0.id == location.profileID
        }), let pageIndex = configuration.profiles[profileIndex].pages.firstIndex(where: {
            $0.id == location.pageID
        }), let segmentIndex = configuration.profiles[profileIndex].pages[pageIndex]
            .segments.firstIndex(where: { $0.slotIndex == location.slotIndex }),
              case .command(let reference) = configuration.profiles[profileIndex]
              .pages[pageIndex].segments[segmentIndex].content else {
            throw CommandWheelProfileEditError.segmentNotFound
        }
        configuration.profiles[profileIndex].pages[pageIndex].segments[segmentIndex]
            .content = .command(try update(reference))
    }

}
