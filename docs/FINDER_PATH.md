# Copy Current Finder Path

Finder Path is a first-party launcher application with one registered Copy Current Finder Path tool. Opening the application is inert. Invoking the tool attempts a copy without prompting; if macOS requires consent, the original explanation stays visible until the user chooses Allow Finder Access and Copy. Nothing observes Finder in the background.

## Selection behavior

- One selected item in Finder’s front folder window: copy that item’s plain POSIX path.
- No selection: copy the current target folder of that window.
- More than one selected item: copy nothing and ask the user to select one item or deselect everything.
- No Finder folder window: copy nothing and explain that a folder window is required. Desktop-only selection is deliberately unsupported.
- Virtual/non-file targets, malformed or oversized replies, and changed/closed windows: copy nothing with recovery guidance.

The front Finder folder window is used while Commandly is foreground. Only concrete local file URLs are accepted; a mounted volume’s `/Volumes/...` path can qualify. Computer and other unsupported container classes are rejected. The folder fallback accepts only Finder’s folder, disk or desktop-container class plus a concrete local URL. Finder search/virtual views are supported only when Finder actually reports one of these concrete targets; there is no fabricated path for Recents, AirDrop or other virtual locations. Native behavior on those views remains an acceptance item.

The text is percent-decoded once, not shell-escaped, and preserves spaces, Unicode and punctuation. NUL, line breaks, parent traversal components and remote URL authorities are refused. The command does not resolve symbolic links or Finder aliases, acquire file grants, open files, read contents or send paths to AI providers. Reading an alias item’s own URL does not request its original-item property.

## Native and permission boundary

The existing sandbox already declares `com.apple.security.automation.apple-events` and a Finder-only `com.apple.security.temporary-exception.apple-events` entry. This feature adds no entitlement, helper, sandbox exception, AppleScript evaluator, shell, private API, accessibility grant or third-party package. The NSAppleEvents usage explanation and permission documentation must include the new explicit read/copy benefit. Generic `SystemPermissionService.appleEvents` remains unchanged; this feature uses a specific Finder get-data permission check rather than pretending all Automation targets share a state.

The installed Apple Finder dictionary `/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef` declares the public `selection` (`sele`), item `URL` (`pURL`), item class (`pcls`), Finder window (`brow`), window target (`fvtg`) and window ID (`ID  `) properties. `FinderAppleEventCodec` builds only fixed `core/getd` object-specifier events. Selection results are zero or one bounded object reference; that reference is used only as the container of the fixed URL-property read. Unknown external tool arguments never become event syntax.

`NativeFinderProcessProvider` identifies the running Finder by exact bundle ID, fixed system application URL, and actual executable path. Public `proc_pidinfo(PROC_PIDTBSDINFO)` supplies its exact kernel birth time as integer seconds and microseconds; `proc_pidpath` confirms the system Finder executable. Two metadata reads bracket fresh application checks and must agree before an identity is returned. The process ID and birth stamp are then checked before/after each Finder snapshot. This does not rely on `NSRunningApplication.launchDate`: Apple's installed AppKit header explicitly says that property can be absent for applications launched outside LaunchServices. Missing, denied, malformed, changed, or untrusted process metadata fails closed; there is no PID-only or invented timestamp fallback.

The libproc reads run on `NativeFinderProcessMetadataReader`’s dedicated serial executor. All synchronous event/TCC work runs on `NativeFinderPathProbe`’s separate dedicated serial executor, not MainActor or a cooperative worker. Process metadata reads do not inspect Finder windows/selections or request Automation permission. [Apple’s NSAppleEventDescriptor API](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor) provides typed descriptor construction and sending. The installed AppKit, libproc, proc_info, NSAppleEventDescriptor and AppleEvents headers confirm the public APIs and flags.

`AEDeterminePermissionToAutomateTarget` checks the specific get-data event with `askUserIfNeeded=false`. True is used only for the visible Allow action. Apple documents that consent may block the calling thread for an unbounded user interaction, so the UI remains cancellable on a separate actor. The OS consent dialog itself cannot be cancelled by this feature. [Apple’s Automation security explanation](https://developer.apple.com/videos/play/wwdc2019/701/)

Subsequent read events combine WaitForReply, NeverInteract, DontRecord, DontReconnect and DoNotPromptForUserConsent. They target the captured running process, do not activate/launch Finder, and do not silently prompt after revocation. Each read event has a maximum 1.5-second native timeout; the three/four-event snapshot shares a five-second event deadline. Permission checking and an OS-owned consent dialog are outside that event deadline. Replies are capped at 64 KiB before inspecting payloads, a single selected reference at 32 KiB, and returned URL/path text at 16 KiB. These bound application processing after Apple’s IPC API returns; Commandly cannot set a receive-allocation cap inside the OS’s reply transport.

The existing temporary exception is documented by [Apple’s sandbox entitlement reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html). Reusing it does not establish App Store acceptance or prove signed native TCC behavior; those remain release/native acceptance concerns.

## Cancellation, freshness and privacy

`FinderPathReader` creates one short-lived single-use token. The model always consumes the token through validation, even if cancellation occurred after capture. Validation checks the same process identity, window ID, exact selection reference and path with a fresh read. A new capture invalidates an older request, and the token expires after ten seconds using a monotonic clock. No stale/expired/forged/replayed token can authorize copy. Failed or cancelled validations consume the token.

The final main-actor copy has no suspension between cancellation/generation checks and the clipboard commit. No platform API makes Finder state and clipboard writing atomic; Finder can still change after its last reply. The feature does not claim to eliminate that final cross-process race. An already-completed clipboard write cannot be recalled by Escape.

Paths and native context are transient, not logged, persisted, indexed or added to a Finder history. The model retains only a generic success/failure message, never the returned path. Copied text enters the general clipboard and may be captured by Commandly Clipboard History when enabled, or by another clipboard manager. No read grants are shared with Finder AI.

## Accessibility and verification

The original UI has labeled text/buttons and headings, a scrollable explanation at compact/large-text sizes, a Return default action, Command-K typed actions, and Escape cancellation/back behavior. Permission denial includes the System Settings → Privacy & Security → Automation recovery path. Settings opening is explicit and uses Commandly’s pinned System Settings adapter; it does not toggle permissions.

Tests construct generated Apple-event descriptors, inject a recording native transport/process provider, use a monotonic test clock and controlled continuations, and inject a recording clipboard. They cover URL validation/encoding, descriptor grammar, cardinality, reply bounds, denied/missing Finder, explicit consent, serial off-main execution, native timeout parameters, window/process/selection/path changes, token expiry/replay, cancellation/restart, disabled actions and recovery. No test contacts real Finder, triggers TCC, reads user files or touches the general clipboard.

Generated process-provider tests also cover exact kernel birth time without LaunchServices metadata,
untrusted/absent/duplicate/terminated applications, wrong PID or executable, malformed birth stamps,
same-PID reuse differing by one microsecond, metadata denial, and cancellation before a native call.
The isolated process-identity suite passes 26 tests in five suites with Swift 6 strict concurrency.
A separate metadata-only unsandboxed diagnostic confirmed the observed Finder process has a nil
LaunchServices date while public BSD metadata and its executable path remain available and stable.
That diagnostic sent no Apple events and is not evidence of signed App Sandbox or TCC acceptance;
the root-owned signed native check remains required.

The DEBUG-only fixture labels a nonexistent generated path and uses the real model and token reader with generated context. Its default copier writes the generated text only after explicit action; test callers inject a recorder. It never silently substitutes for native behavior.

For signed native acceptance, `--commandly-productivity-fixture --commandly-live-finder-path`
selects the real Finder Path adapter while keeping the other productivity services generated.
The override is DEBUG-only and never prompts or reads Finder at launch. The normal explicit
Copy → explanation → Allow flow and macOS consent still apply. Native tests use a deliberately
opened generated folder; this override is not evidence that Finder access has been granted.

Root `make verify` passed after the process-identity correction in
`/tmp/commandly-video-verify-sept17-finder-identity.log`, including all Finder suites and the new
kernel-identity test cases. Signed native acceptance remains required. Generated-fixture UI checks
do not prove permission granting, Finder descriptor conventions or special-location behavior.
Native tests must use a deliberately opened generated test folder after authorization, with one
selection, none, multiple, closed window, denied permission and cancelled work; no settings or
source-file mutation is part of this feature.
