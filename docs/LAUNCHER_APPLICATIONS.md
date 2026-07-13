# Launcher Applications

Commandly treats each built-in capability as a launcher application. Clipboard History, File Search,
and action-only entries such as Open Settings all use the same registration boundary without forcing
their internal screens or domain behavior into a common feature model.

## Architecture

The application path has five layers:

1. `LauncherApplicationDefinition` declares identity, type, hierarchy, defaults, discovery metadata,
   and an optional configuration schema.
2. `LauncherApplication` attaches launch behavior to a launchable definition.
3. `LauncherApplicationRegistry` is the single source of truth for hierarchy, resolved settings,
   discovery, enablement, and launch lookup.
4. A view application constructs its own strongly typed model and wraps it once in a
   `LauncherApplicationSession`.
5. `LauncherRootView` hosts the active session dynamically. It never switches on a concrete
   application identifier.

Type erasure is limited to `LauncherApplicationSession`, where dynamic registration requires it.
Feature models and SwiftUI views remain concrete and testable. The session contract intentionally
contains only shell concerns: status, footer/menu actions, selection movement, action dispatch, and
lifecycle cleanup.

## Adding an application

1. Add the feature model, services, and views under the owning launcher feature folder.
2. Conform the model to `LauncherApplicationModel`. Keep domain behavior in services/models and keep
   the conformance limited to shell coordination.
3. Add a small `LauncherApplication` type under `Commandly/Scenes/Launcher/Applications`. Declare its
   typed `definition`, including its parent and configuration fields. Its
   `launch(in:)` reads resolved configuration from the context, creates the model with
   initializer-injected dependencies, and returns a session.
4. Register that application in `LauncherApplicationRegistry.makeBuiltIn()`.
5. Add a registry/session test and focused model tests. No `LauncherRootView` or route switch change
   should be necessary.

Dependencies shared by one application are grouped in a focused service value such as
`FileSearchApplicationServices` and injected when the application is registered. The launch context
contains only shell navigation, so adding a feature does not grow a cross-application service
locator. Add a focused group rather than expanding unrelated initializers or reaching into global
state.

## Definitions and hierarchy

Every registered node has one of these roles: Group, AI Extension, Extension, Command, or
Application. A group is definition-only; other roles may attach a launch implementation. `parentID`
creates an arbitrary-depth tree. Parents must be registered before children, identifiers and field
variables must be unique, and selection defaults must reference declared options.

The generic Applications settings page derives its entire hierarchy and inspector from these
definitions. Aliases and global shortcuts are editable directly in the hierarchy table; the
selected application's inspector is reserved for enablement and schema-defined configuration.
Adding an application must not require another settings-page branch.

Supported non-secret configuration field kinds are text, toggle, integer, decimal, and selection.
Each field declares a stable variable, title, optional description and placeholder, default value,
and selection options when applicable. Resolved values are supplied through
`LauncherApplicationContext.settings`; application behavior must consume any field it declares.

Per-application aliases, global hotkeys, enablement overrides, and configuration values persist in
`LauncherApplicationPreferencesStoring`. Disabling a group effectively disables all descendants.
Disabled descendants are excluded from discovery and global shortcut registration. Aliases are
empty until the user enters them in Settings, then are added to command search keywords. Carbon
global shortcuts do not request Accessibility access;
reserved and duplicate shortcuts remain unregistered and surface an issue in Settings.

Only non-secret values belong in this schema or UserDefaults store. A future credential field must
use SecurityKit-backed storage and a separate privacy review.

## Reusing screens

Browser-style applications may use `LauncherApplicationScreen`, which supplies the established
Commandly search/filter/sidebar/detail structure. Its companion components provide shared selection
rows, empty states, and metadata rows. The application supplies feature-specific list, preview,
filter, and action content.

An application with a different layout should provide its own SwiftUI surface. Reuse is opt-in;
the registry does not require every application to look alike.

An application may own internal navigation and multiple feature screens inside its concrete model
and root surface. That internal routing remains private to the application session unless the
launcher shell genuinely needs to coordinate it.

## Boundaries

- A registered Commandly application is not an installed macOS application. Installed apps remain
  search results opened through `ApplicationOpening`.
- `CommandManifest` remains the discovery contract from CommandKit; app-target presentation stays in
  the launcher application layer.
- Registration must reject duplicate identifiers.
- Closing or leaving an application session must call its lifecycle cleanup.
- Applications must not log queries, clipboard contents, file paths, previews, or indexed contents.
- New permission behavior still requires the documented contextual permission flow.
