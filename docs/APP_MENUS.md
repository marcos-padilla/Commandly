# App Menus

The sandboxed launcher provides **App Menus**, **Search Current App Menus**, and **Favorite App Menus**. An explicit launch requests one current-app menu snapshot. Search stays local; invoking sends only a session-scoped opaque handle. Native menu reads and AXPress live only in the separately signed optional companion.

## Access and privacy

The companion capability starts disabled for every authenticated connection. System Integration exposes an explicit App Menus toggle only when the helper advertises the reviewed capability. Accessibility is checked without prompting; its existing system grant is separate from the feature opt-in. Construction, metadata checks and favorites loading do not read menus. Enabling only observes activation identities; it performs no AX capture.

The helper remembers one external app with kernel process birth, executable path, bundle identity and epoch. The main app PID comes from the authenticated incoming XPC callback, never caller data. Activation, lock/session-loss hooks and disconnection revoke authority. A snapshot pins its context until explicit launcher release; refresh cannot silently retarget it after an external app switch. The public workspace session/sleep hooks do not claim complete screen-lock notification delivery.

A dedicated serial executor performs bounded AX operations off the main actor. Native messages are capped at 100 ms each within the unchanged five-second request deadline. Traversal stops at 500 nodes and 12 path components. Snapshot handles expire after 30 seconds and are consumed on invocation. Before AXPress, the worker resolves the entire menu path again, validates exact role/title/identifier/shortcut/index fingerprint, checks every enabled ancestor and leaf, and checks the current app identity/lease again. No private API, shell, AppleScript, raw PID request, arbitrary AX attribute, or automatic retry is exposed. macOS offers no atomic identity-validation-to-AXPress transaction.

AX success is reported as accepted, not proof of the app’s semantic result. A failed/timed-out AXPress reports an unknown outcome; users should check the target app before retrying. The launcher clears handles on dismissal and deactivation, with generation checks rejecting late results.

Favorites contain only bundle ID and hashes/indices of identity path components (maximum 100). They do not store menu titles, snapshots, handles, search queries or invocation history. They live in app-owned Application Support with bounded versioned JSON, private file permissions, no symlink target, and atomic replacement. Menu renaming, reordering or localization may invalidate a favorite. Hashes are identifiers, not encryption; they are not claimed to hide a guessable command.

## Integration and evidence

The source-reviewed integration enables `CompanionAppMenuReleaseGate.reviewed` and keeps explicit per-connection opt-in. Both main bound allowlists and the helper factory are wired to that gate; the named metadata engine receives no action handlers. Existing metadata/authentication/deadline policy is unchanged.

September 17, 2026: the actual copied SystemCompanionKit + Infrastructure graph, native menu adapter, app model/view, favorites adapter and Settings composition compiled with Swift 6 complete concurrency and warnings as errors. Twenty-two generated tests in three suites passed without native AX, permission or registration activity. Root application build, signed helper runtime and real menu invocation remain integration/native acceptance gates. No native completion is claimed from generated tests.
