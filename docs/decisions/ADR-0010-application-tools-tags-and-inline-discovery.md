# ADR-0010: Application-owned tools, tags, typed commands, and inline local discovery

- Status: Accepted
- Date: 2026-07-25

## Context

ADR-0004 established registered launcher applications, and ADR-0005 added a configurable
definition hierarchy. The resulting catalog still treated each application as one launchable
command. It could not distinguish an application surface from a focused action that application
exposes, assign a global shortcut to that focused action, or parse an argument-bearing phrase such
as `kill port 3000` without adding feature-specific routing to the launcher.

Root search also required users to open the Clipboard History or File Search application before
searching their local content. Finally, the alias-only discovery setting allowed only one
user-authored term and did not expose the built-in vocabulary that already drove search.

## Decision

Extend the app-target launcher registry without moving presentation or native feature behavior into
CommandKit.

- A `LauncherApplication` declares application-owned tool definitions and optional typed-command
  parsers in addition to its application definition.
- A tool is a launchable registry node with kind `Tool` and the owning application as its parent.
  It has its own manifest, enablement, discovery tags, and optional Carbon global shortcut, but its
  implementation remains in the owning application.
- A non-command application receives one generic Open tool by default. Applications replace that
  default when they need a focused set, such as Shelf entry modes, Color Tools screen sampling,
  Microphone and Highlight toggles, or Port Manager inspection and termination review.
- Definition tags are built-in discovery metadata and remain available. Users may add bounded,
  normalized tags per application or tool in Settings. Legacy aliases remain part of resolved search
  metadata for compatibility, but the Settings surface presents the multi-value tag model.
- A typed command is a declarative, exact-query parser that returns a typed `CommandReference` to an
  owned tool. It is not another registry node and cannot receive a separate shortcut. Its syntax and
  examples are shown under the owning application in Settings.
- Effectively enabled application and tool manifests enter the same CommandKit catalog used by
  launcher search, registered shortcuts, and Command Wheel. The shared executor carries the complete
  `CommandReference`, including arguments, to the owning application.
- Tools explicitly conforming to the background-invocation boundary may run without presenting the
  launcher. Other tools open their owning application at the requested entry point. Existing Carbon
  duplicate and reserved-shortcut handling applies unchanged.
- Shelf's New Shelf and New Shelf from Clipboard combinations are defaults on those two tool
  definitions. `AppRuntime` no longer owns a separate fixed-Shelf shortcut route, so replacement,
  clearing, conflicts, enablement, and execution follow the same registry plan as every other tool.
- Root search supplements the existing SearchKit providers and calculator with application-owned
  typed-command matches, capture-time Clipboard History matches, and bounded File Search index
  matches. Clipboard rows copy the exact stored entry; file rows open the indexed URL. File work is
  cancellable and stale results are rejected.
- Inline Clipboard History and File Search rows are excluded from launcher autocomplete. Their
  queries, values, filenames, paths, and contents are not added to command history or logs.
- A typed command never weakens the target tool's safety boundary. For example, `kill port <number>`
  opens Port Manager with that port selected; a single matching listener still requires local
  confirmation and process-owner revalidation before a graceful termination request.

## Consequences

- Settings can render `Group → Application → Tool` from registry metadata, with applications
  collapsed until the user expands them.
- Focused tools can be searched, assigned to Command Wheel, or launched with their own global
  shortcut without duplicating implementation or adding root-route cases.
- Commands reuse tool availability, argument validation, permissions, and confirmation instead of
  becoming a second execution mechanism.
- Root search can surface authorized files and captured clipboard entries without first presenting
  their full browser applications.
- Built-in and custom tags increase discovery vocabulary without allowing user preferences to erase
  maintained defaults.
- Only explicitly declared stable entry points are tools. Dynamic in-session actions are not
  automatically promoted, and adding a new tool remains an intentional application-level change.
- File results remain limited to the existing authorized local index, and clipboard matching uses
  only data already captured or enriched when the entry was recorded.

## Rejected alternatives

- Treat every in-session action as a global tool: action availability often depends on transient
  selection or state and would create unstable shortcut targets.
- Give parsed commands their own manifests and shortcuts: this duplicates the target tool's
  availability and execution semantics.
- Let typed commands execute arbitrary shell strings: this violates Commandly's security boundary
  and bypasses typed validation and local confirmation.
- Re-run clipboard OCR, file extraction, or filesystem scans for each root query: this would put
  private, expensive work on the keystroke path.
- Remove built-in tags when users customize discovery: maintained search terms must continue to work
  after preference changes.
