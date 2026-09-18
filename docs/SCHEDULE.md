# My Schedule

My Schedule is a read-only native Calendar application. It displays upcoming events from the
accounts already configured in macOS, helps users review and open an exact meeting destination,
and can automatically open one explicitly armed occurrence while Commandly remains running.
It implements the schedule, join, and optional autojoin behaviors shown at 2:44–2:54 in the
[reference video](https://www.youtube.com/watch?v=G7_7F_FBqQE). This is an original Commandly UI.

## User behavior

- Open **My Schedule** or **Open My Schedule**. The application checks Calendar permission without
  prompting. **Grant Calendar Access** explains the benefit before invoking the existing permission
  service. Denied, restricted, and write-only access lead to Calendar privacy settings.
- Choose **Today**, **Next 7 Days**, or **Next 30 Days**, then optionally choose a calendar. Search
  matches event title, calendar name, and location locally. Past events are removed from the view;
  all-day, canceled, and declined events remain labeled when they intersect the requested range.
- Navigate events with Up/Down. Return opens a meeting review when the event has eligible links.
  **Join Next Meeting** opens the next eligible event's review; it does not open a URL itself.
- Review the exact HTTPS destination. For multiple links, choose one explicitly. **Join Meeting**
  re-reads the event before handing the exact destination to the existing URL opener. Search,
  selection, refresh, and link extraction never open links.
- **Automatically Join This Occurrence…** opens a separate review. **Enable Autojoin** arms one
  future timed event; it replaces any previously armed occurrence. **Cancel Automatic Joining**
  disarms it. Closing the launcher preserves the explicitly armed plan; quitting Commandly does not.
- Escape cancels a review, then clears search, then returns to the launcher. Standard shared
  keyboard controls and Command-K expose the same actions as the visible buttons.

Loading, empty results, filtered results, truncation, read failures, denied access, and settings
recovery are represented explicitly. The shared launcher status area displays join/autojoin results.
An event changed during review closes that review on refresh. Joining also rechecks the original
event and exact link independently, so a stale visible snapshot cannot redirect a confirmed action.

## Ownership and composition

| Layer | Source |
| --- | --- |
| Sendable occurrence, event, query, result, error, and read-only contracts | `Packages/Sources/Infrastructure/Schedule.swift` |
| EventKit actor and bounded snapshot projection | `Commandly/Services/Schedule/NativeScheduleService.swift` |
| Local URL extraction and validation | `Commandly/Services/Schedule/ScheduleMeetingLinkExtractor.swift` |
| Explicit one-occurrence runtime coordinator | `Commandly/Services/Schedule/ScheduleAutoJoinCoordinator.swift` |
| Injectable deadlines and Calendar/wake notifications | `Commandly/Services/Schedule/ScheduleRuntimeSupport.swift` |
| Focused services bundle and inert fixtures | `Commandly/Services/Schedule/ScheduleApplicationServices.swift` |
| UI state and feature views | `Commandly/Scenes/Launcher/Commands/Schedule/` |
| Application, tools, and in-app documentation | `Commandly/Scenes/Launcher/Applications/ScheduleApplication.swift`, `Documentation/ScheduleDocumentation.swift` |

`AppRuntime` owns the native reader and one `ScheduleAutoJoinCoordinator`, injects a shared
`ScheduleApplicationServices` bundle through `LauncherApplicationRegistry`, and cancels the
coordinator during teardown. No runtime constructor arms a plan or requests access. The debug
fixture uses `.inMemory`; tests inject fake permissions, readers, URL openers, notifications, and
deadlines. Domain contracts do not import the app, SwiftUI, or EventKit.

## Calendar and privacy boundary

The existing Calendar entitlement and both modern/legacy Calendar usage strings already cover this
feature. No new entitlement or permission is added. macOS 14+ requires **Full Access** to read events;
the adapter never calls event write APIs. The existing `PermissionServicing` dependency owns the
explicit access request, and `PrivacySettingsOpening` owns recovery.

`NativeScheduleService` lazily creates its EventKit store only after authorized preflight. It confines
EventKit objects and synchronous enumeration to its actor, checks task cancellation, and rechecks
permission before returning a detached value snapshot. No EventKit reference crosses actor boundaries.
Occurrence identity combines local calendar ID, EventKit event identifier, and original occurrence
date. It avoids external identifiers, which can collide. Identity changes after sync fail closed for
an armed plan.

Each query spans at most 31 days and returns at most 500 events; the view requests 200. Native
enumeration scans at most five times the return limit and retains the earliest occurrences encountered.
Because EventKit enumeration is unordered, hitting either bound marks the snapshot truncated. The
UI recommends a smaller date range; it does not claim that a truncated view contains every next event.
Event titles, calendar names, locations, note parsing, and destination counts are bounded.

Only titles, dates, local calendar identity, bounded location, participation flags, and extracted links
are projected. Full event notes and attendee details are not retained. Snapshots, meeting tokens,
search, and armed event details remain in process memory; Schedule adds no persistence, history,
logging, upload, clipboard write, or network request. An explicit join hands the URL to its default
application, which may follow its own account and permission flows.

## Meeting destination and automatic joining

Links must be HTTPS with an ordinary ASCII hostname, no credentials or control characters, no
nonstandard port, and no numeric/local host. Extraction checks the event URL, bounded location, and
bounded notes, deduplicating up to 16 candidates. It never fetches a link, resolves a redirect, or strips
meeting query tokens. Unknown valid HTTPS hosts can be reviewed and joined manually.

Automatic joining additionally recognizes known meeting paths on Google Meet, Zoom, Microsoft Teams,
and Webex domains. Suffix matching respects domain boundaries; a misleading hostname such as
`zoom.us.example.com` is not treated as Zoom. An agenda or sign-in link on a recognized domain is
not sufficient to arm a plan.

The coordinator keeps one exact event and destination. A fakeable absolute-date scheduler revalidates
at the start time or every 30 seconds while armed; Calendar-change and wake notifications trigger the
same check. These are runtime deadlines, not sleeps used for synchronization. Immediately before
opening, the reader must return the same occurrence, start/end times, and exact URL, and the event
must remain neither canceled nor declined. A missing event, changed identity/time/link, permission
loss, or read error stops the plan. If the app wakes more than 60 seconds after the start, the plan is
skipped. An opening attempt claims the occurrence before awaiting the native handoff, preventing
duplicate automatic opens or retries after uncertain failures. Manually joining an armed occurrence
first cancels its pending automatic action. An in-flight occurrence guard prevents a simultaneous
manual join from duplicating an automatic URL handoff; later explicit manual retries remain possible.
Joined occurrence markers retain opaque identity and end time only; subsequent join/arm interactions
prune markers for events that have ended.

## Validation and limits

The focused suites are:

- `InfrastructureTests/ScheduleTests`: bounded query, sorted/limited fixture snapshots, distinct
  calendar and recurring occurrence identity.
- `CommandlyTests/ScheduleMeetingLinkTests`: exact tokens, bounded extraction, unsafe URL rejection,
  misleading provider hostnames, and manual-only unknown destinations.
- `CommandlyTests/ScheduleApplicationTests`: contextual permission and settings recovery, no implicit
  read/prompt/open, filters, date range, explicit exact-link confirmation, stale event handling,
  revocation, errors, session lifecycle, and application/tool registration.
- `CommandlyTests/ScheduleAutoJoinTests`: opt-in/deadline behavior, cancel, late wake, changed events,
  eligibility, access loss, no automatic retry, manual duplicate suppression, and recurrence identity.

All tests use fixture event data and fake side-effect boundaries. They do not access a live Calendar,
open a meeting, request real permissions, or wait for wall-clock time. The parent task runs the
combined application build, focused tests, and `make verify`; this document describes the covered
behavior without claiming a live permission or meeting-provider smoke test.

This slice does not create or edit events, configure calendar accounts, persist an agenda or autojoin
plan, launch Commandly at a meeting deadline, provide a camera preview, or record meetings. It does
not control a provider's camera/microphone or promise to enter a meeting after opening its link.
Those broader video capabilities remain separate tracked requirements.
