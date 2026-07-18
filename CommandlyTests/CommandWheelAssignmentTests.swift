import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Launcher Command Wheel assignment")
@MainActor
struct CommandWheelAssignmentTests {
    @Test
    func installedApplicationSearchPreservesTypedBundleIdentifierReference() async throws {
        let fixture = makeAssignmentFixture()
        let bundleIdentifier = "com.example.TypedApplication"
        let viewModel = LauncherViewModel(
            applicationRegistry: LauncherApplicationRegistry(),
            commandWheelAssignmentStore: fixture.store,
            applicationQuery: InMemoryInstalledApplicationQuery(
                applications: [
                    InstalledApplication(
                        bundleIdentifier: bundleIdentifier,
                        name: "Typed Application",
                        path: "/Applications/Typed Application.app"
                    ),
                ]
            ),
            placeholderItems: []
        )

        viewModel.query = "Typed Application"
        await viewModel.flushSearchForTesting()
        let item = try #require(viewModel.rootItems.first(where: {
            $0.id == "app:\(bundleIdentifier)"
        }))
        let reference = try #require(viewModel.commandWheelReference(for: item))

        #expect(
            reference == BuiltInCommandReference.openInstalledApplication(
                bundleIdentifier: bundleIdentifier
            )
        )
        #expect(
            reference.arguments[BuiltInCommandArgumentName.bundleIdentifier]
                == .string(bundleIdentifier)
        )

        viewModel.presentContextActions(for: item)
        #expect(viewModel.showsApplicationActionsPanel)
        #expect(
            viewModel.filteredApplicationActions.contains {
                $0.id == LauncherCommandWheelActionID.add
                    && $0.title == "Add to Command Wheel…"
            }
        )

        viewModel.presentCommandWheelAssignmentForInstalledApplication(
            bundleIdentifier: bundleIdentifier
        )
        await waitForAssignmentPresentation(viewModel)
        #expect(viewModel.commandWheelAssignmentModel?.reference == reference)
    }

    @Test
    func registeredSearchContextActionUsesExactSharedCommandReference() async throws {
        let fixture = makeAssignmentFixture()
        let viewModel = LauncherViewModel(
            commandWheelAssignmentStore: fixture.store,
            placeholderItems: []
        )
        let item = try #require(viewModel.rootItems.first(where: {
            if case .launchApplication = $0.action { return true }
            return false
        }))
        let expectedReference = try #require(viewModel.commandWheelReference(for: item))

        viewModel.presentContextActions(for: item)

        #expect(viewModel.showsRegisteredCommandActionsPanel)
        #expect(viewModel.filteredRegisteredCommandActions.map(\.title) == [
            "Add to Command Wheel…",
        ])
        viewModel.performRegisteredCommandAction(LauncherCommandWheelActionID.add)
        await waitForAssignmentPresentation(viewModel)
        #expect(viewModel.commandWheelAssignmentModel?.reference == expectedReference)
    }

    @Test
    func assignmentPresentationWaitsForDurableProfilePreload() async throws {
        var durable = CommandWheelDefaults.configuration
        durable.profiles[0].name = "Durable Profile"
        durable.profiles[0].pages[0].segments[0].content = .empty
        let repository = DelayedAssignmentRepository(configuration: durable)
        let store = CommandWheelProfileStore(
            repository: repository,
            initialConfiguration: CommandWheelDefaults.configuration
        )
        let viewModel = LauncherViewModel(
            commandWheelAssignmentStore: store,
            placeholderItems: []
        )

        viewModel.presentCommandWheelAssignmentForInstalledApplication(
            bundleIdentifier: "com.example.Durable"
        )
        await repository.waitUntilLoadStarts()
        #expect(viewModel.commandWheelAssignmentModel == nil)

        await repository.releaseLoad()
        await waitForAssignmentPresentation(viewModel)

        #expect(viewModel.commandWheelAssignmentModel?.profiles.first?.name == "Durable Profile")
        #expect(store.phase == .ready)
    }

    @Test
    func occupiedDestinationRequiresExplicitReplaceBeforeSaving() async throws {
        let fixture = makeAssignmentFixture()
        var reportedMessages: [String] = []
        let model = try #require(makeModel(fixture: fixture) {
            reportedMessages.append($0)
        })
        model.selectSlot(2)

        #expect(await model.requestAssignment() == false)
        guard case .replaceAssignment(let destination, let occupiedDescription) =
            model.pendingAction else {
            Issue.record("Expected an explicit replacement confirmation")
            return
        }
        #expect(destination.slotIndex == 2)
        #expect(occupiedDescription.contains(BuiltInCommandID.openSettings.rawValue))
        #expect(commandReference(at: 2, in: fixture.store.configurationSnapshot())
            == CommandReference(commandID: BuiltInCommandID.openSettings))

        #expect(await model.confirmPendingAction())
        #expect(commandReference(at: 2, in: fixture.store.configurationSnapshot()) == fixture.reference)
        #expect(customLabel(at: 2, in: fixture.store.configurationSnapshot()) == "Typed Application")
        #expect(reportedMessages.last == "Replaced the occupied slot with Typed Application.")
    }

    @Test
    func exactAssignmentCanMoveThenBeRemoved() async throws {
        let fixture = makeAssignmentFixture()
        let model = try #require(makeModel(fixture: fixture))
        let source = try #require(model.existingAssignments.first).location
        model.selectSlot(3)

        #expect(await model.requestMove(from: source))
        #expect(commandReference(at: 0, in: fixture.store.configurationSnapshot()) == nil)
        #expect(commandReference(at: 3, in: fixture.store.configurationSnapshot()) == fixture.reference)

        let moved = try #require(model.existingAssignments.first)
        #expect(moved.location.slotIndex == 3)
        model.requestRemoval(of: moved)
        guard case .remove(let removalLocation, _) = model.pendingAction else {
            Issue.record("Expected explicit removal confirmation")
            return
        }
        #expect(removalLocation == moved.location)
        #expect(await model.confirmPendingAction())
        #expect(model.existingAssignments.isEmpty)
        #expect(commandReference(at: 3, in: fixture.store.configurationSnapshot()) == nil)
    }

    @Test
    func newSubmenuAndContainedCommandAreSavedAtomically() async throws {
        let fixture = makeAssignmentFixture()
        let model = try #require(makeModel(fixture: fixture))
        model.selectSlot(5)
        model.newSubmenuName = "Work Tools"
        model.newSubmenuChildSlotIndex = 3

        #expect(await model.requestNewSubmenu())

        let configuration = fixture.store.configurationSnapshot()
        let profile = try #require(configuration.profiles.first)
        let root = try #require(profile.pages.first(where: { $0.id == profile.rootPageID }))
        let parentSegment = try #require(root.segments.first(where: { $0.slotIndex == 5 }))
        guard case .submenu(let childPageID) = parentSegment.content else {
            Issue.record("Expected the selected parent slot to contain the new submenu")
            return
        }
        let child = try #require(profile.pages.first(where: { $0.id == childPageID }))
        #expect(child.name == "Work Tools")
        #expect(child.segments.count == profile.interaction.visibleSlotCount)
        #expect(
            child.segments.first(where: { $0.slotIndex == 3 })?.content
                == .command(fixture.reference)
        )
        #expect(
            child.segments.first(where: { $0.slotIndex == 3 })?.customLabel
                == "Typed Application"
        )
    }

    @Test
    func assignmentListMatchesFullReferenceAndRevealUsesInjectedLocation() throws {
        let fixture = makeAssignmentFixture()
        var revealedLocation: CommandWheelSlotLocation?
        let optionalModel = CommandWheelAssignmentModel(
            reference: fixture.reference,
            commandTitle: "Typed Application",
            commandSystemImage: "app.fill",
            store: fixture.store,
            reportStatus: { _ in },
            revealAssignment: { revealedLocation = $0 }
        )
        let model = try #require(optionalModel)

        let assignments = model.existingAssignments
        #expect(assignments.count == 1)
        let assignment = try #require(assignments.first)
        #expect(assignment.location.slotIndex == 0)
        #expect(assignment.reference == fixture.reference)
        #expect(assignment.locationDescription == "Default › Main › Slot 1")

        model.reveal(assignment)
        #expect(revealedLocation == assignment.location)
    }

    private func makeModel(
        fixture: AssignmentFixture,
        reportStatus: @escaping @MainActor (String) -> Void = { _ in }
    ) -> CommandWheelAssignmentModel? {
        CommandWheelAssignmentModel(
            reference: fixture.reference,
            commandTitle: "Typed Application",
            commandSystemImage: "app.fill",
            store: fixture.store,
            reportStatus: reportStatus,
            revealAssignment: { _ in }
        )
    }
}

@MainActor
private func waitForAssignmentPresentation(_ viewModel: LauncherViewModel) async {
    for _ in 0 ..< 100 where viewModel.commandWheelAssignmentModel == nil {
        await Task.yield()
    }
    #expect(viewModel.commandWheelAssignmentModel != nil)
}

@MainActor
private struct AssignmentFixture {
    let reference: CommandReference
    let store: CommandWheelProfileStore
}

private actor DelayedAssignmentRepository: CommandWheelProfileRepository {
    private var configuration: CommandWheelConfiguration
    private var didStart = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(configuration: CommandWheelConfiguration) {
        self.configuration = configuration
    }

    func load() async -> CommandWheelConfiguration {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if isReleased == false {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return configuration
    }

    func save(_ configuration: CommandWheelConfiguration) {
        self.configuration = configuration
    }

    func exportProfiles(ids: Set<UUID>?) throws -> Data {
        throw CommandWheelRepositoryError.noProfilesSelectedForExport
    }

    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>?
    ) throws -> CommandWheelImportResult {
        throw CommandWheelRepositoryError.malformedImport
    }

    func waitUntilLoadStarts() async {
        if didStart { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseLoad() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private func makeAssignmentFixture() -> AssignmentFixture {
    let exactReference = BuiltInCommandReference.openInstalledApplication(
        bundleIdentifier: "com.example.TypedApplication"
    )
    let differentArguments = BuiltInCommandReference.openInstalledApplication(
        bundleIdentifier: "com.example.DifferentApplication"
    )
    var configuration = CommandWheelDefaults.configuration
    configuration.profiles[0].pages[0].segments[0].content = .command(exactReference)
    configuration.profiles[0].pages[0].segments[1].content = .command(differentArguments)
    configuration.profiles[0].pages[0].segments[2].content = .command(
        CommandReference(commandID: BuiltInCommandID.openSettings)
    )
    let repository = InMemoryCommandWheelProfileRepository(configuration: configuration)
    let store = CommandWheelProfileStore(
        repository: repository,
        initialConfiguration: configuration
    )
    return AssignmentFixture(reference: exactReference, store: store)
}

@MainActor
private func commandReference(
    at slotIndex: Int,
    in configuration: CommandWheelConfiguration
) -> CommandReference? {
    guard let profile = configuration.profiles.first,
          let root = profile.pages.first(where: { $0.id == profile.rootPageID }),
          let segment = root.segments.first(where: { $0.slotIndex == slotIndex }),
          case .command(let reference) = segment.content else {
        return nil
    }
    return reference
}

@MainActor
private func customLabel(
    at slotIndex: Int,
    in configuration: CommandWheelConfiguration
) -> String? {
    guard let profile = configuration.profiles.first,
          let root = profile.pages.first(where: { $0.id == profile.rootPageID }),
          let segment = root.segments.first(where: { $0.slotIndex == slotIndex }) else {
        return nil
    }
    return segment.customLabel
}
