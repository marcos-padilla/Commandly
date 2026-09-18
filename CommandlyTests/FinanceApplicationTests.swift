import CommandKit
import Foundation
import Testing
@testable import Commandly

struct FinanceApplicationTests {
    @Test
    func dashboardNormalizesSpendAndFindsSevenDayRenewals() throws {
        let calendar = utcCalendar()
        let today = try date(2026, 7, 18, calendar: calendar)
        let monthly = subscription(
            name: "Writing",
            amount: 12,
            cycle: .monthly,
            category: .productivity,
            nextBillingDate: try date(2026, 7, 20, calendar: calendar)
        )
        let annual = subscription(
            name: "Storage",
            amount: 120,
            cycle: .yearly,
            category: .cloudStorage,
            nextBillingDate: try date(2026, 8, 1, calendar: calendar)
        )
        var archived = subscription(
            name: "Old Plan",
            amount: 99,
            cycle: .monthly,
            category: .other,
            nextBillingDate: today
        )
        archived.isActive = false

        let result = FinanceRecurrence.dashboard(
            ledger: FinanceLedger(
                subscriptions: [monthly, annual, archived],
                budgets: []
            ),
            relativeTo: today,
            calendar: calendar
        )

        #expect(result.monthlySpend == 22)
        #expect(result.yearlySpend == 264)
        #expect(result.activePlanCount == 2)
        #expect(result.renewingSoonCount == 1)
        #expect(result.upcomingRenewals.map(\.subscription.name) == ["Writing", "Storage"])
        #expect(result.categorySummaries.map(\.category) == [.productivity, .cloudStorage])
    }

    @Test
    func weeklyPlanExpandsAcrossCalendarMonth() throws {
        let calendar = utcCalendar()
        let plan = subscription(
            name: "Weekly Coaching",
            amount: 25,
            cycle: .weekly,
            category: .education,
            nextBillingDate: try date(2026, 7, 2, calendar: calendar)
        )
        let interval = DateInterval(
            start: try date(2026, 7, 1, calendar: calendar),
            end: try date(2026, 8, 1, calendar: calendar)
        )

        let occurrences = FinanceRecurrence.occurrences(
            for: plan,
            in: interval,
            calendar: calendar
        )

        #expect(occurrences.count == 5)
        #expect(calendar.component(.day, from: occurrences.first ?? .distantPast) == 2)
        #expect(calendar.component(.day, from: occurrences.last ?? .distantPast) == 30)
    }

    @Test
    func monthEndRecurrenceKeepsItsOriginalCalendarAnchor() throws {
        let calendar = utcCalendar()
        let plan = subscription(
            name: "Month End",
            amount: 8,
            cycle: .monthly,
            category: .financialServices,
            nextBillingDate: try date(2026, 1, 31, calendar: calendar)
        )

        let marchRenewal = FinanceRecurrence.nextRenewal(
            for: plan,
            relativeTo: try date(2026, 3, 1, calendar: calendar),
            calendar: calendar
        )

        #expect(calendar.component(.month, from: marchRenewal ?? .distantPast) == 3)
        #expect(calendar.component(.day, from: marchRenewal ?? .distantPast) == 31)
    }

    @Test @MainActor
    func modelPersistsSubscriptionBudgetArchiveAndDeletion() async throws {
        let calendar = utcCalendar()
        let now = try date(2026, 7, 18, calendar: calendar)
        let fixedID = try #require(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let store = InMemoryFinanceStore()
        let model = FinanceViewModel(
            services: FinanceApplicationServices(
                persistence: store,
                now: { now },
                makeID: { fixedID },
                calendar: calendar
            ),
            currencyCode: "USD",
            onGoBack: {}
        )
        await model.load()

        let draft = FinanceSubscriptionDraft(
            subscriptionID: nil,
            name: "  Design Tools  ",
            amountText: "19.99",
            billingCycle: .monthly,
            category: .productivity,
            nextBillingDate: try date(2026, 7, 23, calendar: calendar),
            notes: " Team plan ",
            isActive: true
        )
        #expect(await model.saveSubscription(draft))
        #expect(model.ledger.subscriptions.count == 1)
        #expect(model.selectedSubscription?.id == fixedID)
        #expect(model.selectedSubscription?.name == "Design Tools")
        #expect(model.selectedSubscription?.notes == "Team plan")

        #expect(await model.saveBudget(FinanceBudgetDraft(
            category: .productivity,
            amountText: "50"
        )))
        #expect(model.budget(for: .productivity) == 50)

        let saved = try #require(model.selectedSubscription)
        model.toggleArchive(saved)
        await model.flushPersistenceForTesting()
        #expect(model.ledger.subscriptions.first?.isActive == false)

        let archived = try #require(model.ledger.subscriptions.first)
        model.requestDelete(archived)
        model.confirmDeletion()
        await model.flushPersistenceForTesting()
        #expect(model.ledger.subscriptions.isEmpty)
        #expect(await store.snapshot() == model.ledger)
    }

    @Test @MainActor
    func builtInRegistryDiscoversAndLaunchesFinanceWithoutShellBranch() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            financeServices: .inMemory
        )
        let definition = try #require(registry.definition(for: FinanceApplication.id))
        let application = try #require(registry.application(for: FinanceApplication.id))
        let settings = try #require(registry.resolvedSettings(for: FinanceApplication.id))

        #expect(definition.kind == .application)
        #expect(definition.parentID == BuiltInLauncherApplicationGroup.catalogID)
        #expect(definition.documentation != nil)
        #expect(settings.value(for: "currencyCode") == .text("USD"))
        #expect(registry.allManifests().contains { $0.id == FinanceApplication.id })

        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: settings
        )
        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected Finance to present a session")
            return
        }
        #expect(session.model(as: FinanceViewModel.self)?.currencyCode == "USD")
    }

    @Test @MainActor
    func financeToolsAreRegisteredAndNewSubscriptionOpensTheExistingEditor() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            financeServices: .inMemory
        )
        let tools = registry.children(of: FinanceApplication.id)

        #expect(tools.map(\.id) == [
            FinanceApplication.openToolID,
            FinanceApplication.newSubscriptionToolID
        ])
        #expect(tools.allSatisfy { $0.kind == .tool })
        #expect(tools.allSatisfy { $0.parentID == FinanceApplication.id })
        #expect(registry.owningApplicationID(for: FinanceApplication.openToolID) == FinanceApplication.id)
        #expect(registry.owningApplicationID(for: FinanceApplication.newSubscriptionToolID) == FinanceApplication.id)
        #expect(registry.allManifests().contains { manifest in
            manifest.id == FinanceApplication.newSubscriptionToolID
                && manifest.keywords.contains("new subscription")
        })
        #expect(registry.resolvedSettings(for: FinanceApplication.newSubscriptionToolID) != nil)

        let application = try #require(registry.application(for: FinanceApplication.id))
        let settings = try #require(registry.resolvedSettings(for: FinanceApplication.id))
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: settings
        )

        guard case .present(let openSession) = application.launch(
            toolID: FinanceApplication.openToolID,
            arguments: CommandArguments(),
            in: context
        ) else {
            Issue.record("Expected Open Finance to present a session")
            return
        }
        #expect(openSession.model(as: FinanceViewModel.self)?.presentation == nil)

        guard case .present(let newSubscriptionSession) = application.launch(
            toolID: FinanceApplication.newSubscriptionToolID,
            arguments: CommandArguments(),
            in: context
        ) else {
            Issue.record("Expected New Subscription to present a Finance session")
            return
        }
        let model = try #require(
            newSubscriptionSession.model(as: FinanceViewModel.self)
        )
        guard case .subscription(let draft)? = model.presentation else {
            Issue.record("Expected the existing subscription editor presentation")
            return
        }
        #expect(draft.subscriptionID == nil)
        #expect(draft.name.isEmpty)
    }

    @Test @MainActor
    func jsonStoreRoundTripsVersionedLedgerAtInjectedURL() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Commandly-FinanceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("FinanceLedger.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFinanceStore(fileURL: fileURL)
        let ledger = FinanceLedger(
            subscriptions: [
                subscription(
                    name: "Music",
                    amount: 10,
                    cycle: .monthly,
                    category: .entertainment,
                    nextBillingDate: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            budgets: [FinanceCategoryBudget(category: .entertainment, monthlyLimit: 25)]
        )

        try await store.saveLedger(ledger)
        let loaded = try await store.loadLedger()

        #expect(loaded == ledger)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

private func subscription(
    name: String,
    amount: Decimal,
    cycle: SubscriptionBillingCycle,
    category: FinanceCategory,
    nextBillingDate: Date
) -> FinanceSubscription {
    FinanceSubscription(
        id: UUID(),
        name: name,
        amount: amount,
        billingCycle: cycle,
        category: category,
        nextBillingDate: nextBillingDate,
        notes: "",
        isActive: true,
        createdAt: nextBillingDate,
        updatedAt: nextBillingDate
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    calendar: Calendar
) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
}
