# Finance

Commandly Finance is a local-first registered launcher application for recurring financial commitments. The implemented scope is subscription tracking and subscription-backed category budgets; it is a foundation for broader personal-finance workflows, not a claim that bank aggregation or full accounting already exists.

## Current behavior

- Add and edit active or archived subscriptions with a name, Decimal amount, weekly/monthly/quarterly/yearly billing cycle, category, next billing date, and optional notes.
- Normalize active commitments into monthly and yearly totals without changing the original charge.
- Show active plans, renewals in the next seven days, a 30-day renewal list, and monthly spending by category.
- Expand recurring dates into a calendar month, including multiple weekly occurrences.
- List every supported category and set a monthly subscription budget for each one.
- Search subscriptions and expose create/edit/archive/restore/delete actions through the shared launcher session and Command Wheel-compatible command manifest.

The ledger uses one configured currency. Commandly does not fetch exchange rates, infer tax, or combine mixed-currency amounts.

## Architecture

`Commandly/Services/Finance` owns immutable ledger values, recurrence and aggregation math, and the `FinancePersisting` boundary. The production actor writes one versioned JSON envelope under Commandly's Application Support container with atomic replacement. Tests use `InMemoryFinanceStore`.

`Commandly/Scenes/Launcher/Commands/Finance` owns the `@MainActor` application model and SwiftUI surfaces. `FinanceApplication` declares discovery metadata, documentation, and ledger-currency configuration. `LauncherApplicationRegistry` composes the application without adding a Finance-specific branch to the launcher shell.

## Privacy and permissions

Subscription names, prices, dates, notes, and budgets are private financial records. They are never logged or sent over the network. The feature requests no macOS permission and does not access banks, browsers, email, calendars, or credentials.

The current local file is not separately encrypted by Commandly. It receives the normal protection of the user's macOS account, filesystem, and sandbox container. Bank credentials must never be added to this ledger or to UserDefaults; a future bank connection would require a separate Keychain-backed design and privacy review.

## Accessibility

All navigation and plan-management actions are keyboard reachable. Dashboard metrics, category bars, calendar days, budget progress, icon-only controls, selection state, and destructive confirmation expose text labels that do not rely on color alone.

## Deliberate limitations

The implemented feature does not import transactions, reconcile accounts, forecast cash flow, track income, investments, net worth, debt, tax, or goals; connect to financial institutions; or sync between devices. Those capabilities require separate data contracts, threat modeling, migration design, and explicit user authorization.
