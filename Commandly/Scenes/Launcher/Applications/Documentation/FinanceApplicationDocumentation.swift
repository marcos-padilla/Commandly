import Foundation

extension RegisteredApplicationDocumentation {
    static let finance = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Track recurring subscriptions in a private local ledger, understand monthly and yearly commitments, review renewal dates and categories, and set subscription-backed monthly budgets.",
        sections: [
            DocumentationSection(
                id: "finance.add",
                title: "Add and Manage Subscriptions",
                blocks: [
                    .bullets("finance.add.tools", [
                        "Open Finance opens the overview for browsing subscriptions, renewals, categories, calendars, and budgets.",
                        "New Subscription is a focused launcher tool that opens Finance with a blank subscription editor. It does not create a record until you complete the form and choose Save."
                    ]),
                    .steps("finance.add.steps", [
                        "Open Finance and choose Add Subscription or press Command-N.",
                        "Enter the plan name, price, billing cycle, category, and next billing date. Optional notes stay local with the record.",
                        "Save the plan. Commandly normalizes weekly, monthly, quarterly, and yearly prices for the overview while preserving the original charge amount."
                    ]),
                    .bullets("finance.add.manage", [
                        "Search by name, category, or notes and filter active, archived, or all plans.",
                        "Edit a plan when its price or next billing date changes.",
                        "Archive a cancelled plan without losing its details, or permanently delete it after confirmation."
                    ]),
                    .shortcuts("finance.add.shortcuts", [
                        DocumentationShortcut(id: "finance.add.new", title: "Add a subscription", keys: ["⌘", "N"]),
                        DocumentationShortcut(id: "finance.add.move", title: "Move subscription selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "finance.add.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "finance.add.escape", title: "Clear search, return to overview, or go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "finance.insights",
                title: "Understand Commitments and Renewals",
                blocks: [
                    .bullets("finance.insights.views", [
                        "Overview shows normalized monthly and yearly spend, active plan count, renewals in the next seven days, category spending, and the next 30 days of renewals.",
                        "Categories lists every supported category, including categories with no current plans.",
                        "Calendar expands each active plan's recurrence so weekly plans can appear multiple times in a month.",
                        "Budgets compare monthly subscription commitments with a limit you set for each category."
                    ]),
                    .callout(
                        "finance.insights.currency",
                        DocumentationCallout(
                            kind: .important,
                            title: "One ledger currency",
                            text: "All entered amounts use the Finance ledger currency selected in Applications settings. Commandly does not fetch exchange rates or convert mixed currencies in this initial version."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "finance.privacy",
                title: "Privacy and Current Scope",
                blocks: [
                    .callout(
                        "finance.privacy.local",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Local finance ledger",
                            text: "Subscriptions and budget targets are stored as versioned JSON in Commandly's Application Support container. Financial records are not logged, uploaded, or connected to a bank."
                        )
                    ),
                    .callout(
                        "finance.privacy.scope",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Recurring finance foundation",
                            text: "This version tracks subscriptions and subscription-backed budgets. It does not yet import bank transactions, reconcile accounts, forecast cash flow, track investments, calculate taxes, manage debt, or sync between devices."
                        )
                    )
                ]
            )
        ],
        keywords: [
            "subscription tracker", "recurring spend", "renewing soon", "category spending",
            "calendar", "monthly budget", "local finance", "currency"
        ]
    )
}
