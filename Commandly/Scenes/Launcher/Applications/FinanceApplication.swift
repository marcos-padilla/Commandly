import CommandKit
import SwiftUI

/// Commandly's local-first subscription and recurring-finance workspace.
@MainActor
struct FinanceApplication: LauncherApplication {
    static let id = CommandID(rawValue: "finance.overview")
    static let openToolID = CommandID(rawValue: "finance.overview.tool.open")
    static let newSubscriptionToolID = CommandID(rawValue: "finance.new-subscription")

    static let manifest = CommandManifest(
        id: id,
        title: "Finance",
        subtitle: "Subscriptions, renewals, categories, calendar, and budgets",
        systemImage: "creditcard.and.123",
        category: .productivity,
        mode: .view,
        keywords: [
            "subscription", "subscriptions", "renewal", "spending", "money", "budget", "calendar",
            "finance", "bills", "monthly", "yearly"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: FinanceActionID.newSubscription,
                title: "New Subscription",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 39,
        configurationFields: [
            LauncherConfigurationField(
                id: "ledger-currency",
                variable: "currencyCode",
                title: "Ledger currency",
                description: "The currency used by every amount in the local finance ledger.",
                kind: .selection,
                defaultValue: .text("USD"),
                options: [
                    LauncherConfigurationOption(id: "USD", title: "US Dollar (USD)"),
                    LauncherConfigurationOption(id: "EUR", title: "Euro (EUR)"),
                    LauncherConfigurationOption(id: "GBP", title: "British Pound (GBP)"),
                    LauncherConfigurationOption(id: "CAD", title: "Canadian Dollar (CAD)"),
                    LauncherConfigurationOption(id: "AUD", title: "Australian Dollar (AUD)"),
                    LauncherConfigurationOption(id: "JPY", title: "Japanese Yen (JPY)")
                ]
            )
        ],
        documentation: RegisteredApplicationDocumentation.finance
    )

    private let services: FinanceApplicationServices

    init(services: FinanceApplicationServices = .live) {
        self.services = services
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: Self.openToolID,
                parentID: Self.id,
                title: "Open Finance",
                subtitle: "Review subscriptions, renewals, budgets, and spending",
                systemImage: "creditcard.and.123",
                keywords: ["open", "finance", "subscriptions", "renewals", "money", "budget"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.newSubscriptionToolID,
                parentID: Self.id,
                title: "New Subscription",
                subtitle: "Open Finance with a new subscription form",
                systemImage: "plus.rectangle.on.rectangle",
                order: 1,
                keywords: [
                    "new subscription", "add subscription", "subscription", "renewal", "bill"
                ]
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(opensNewSubscription: false, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case Self.openToolID:
            return makeLaunch(opensNewSubscription: false, context: context)
        case Self.newSubscriptionToolID:
            return makeLaunch(opensNewSubscription: true, context: context)
        default:
            return .message("Finance tool is unavailable.")
        }
    }

    private func makeLaunch(
        opensNewSubscription: Bool,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let currencyCode = context.settings.value(for: "currencyCode")?.textValue ?? "USD"
        let model = FinanceViewModel(
            services: services,
            currencyCode: currencyCode,
            onGoBack: context.navigation.goBack
        )
        if opensNewSubscription {
            model.beginNewSubscription()
        }
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                FinanceView(viewModel: $0)
            }
        )
    }
}
