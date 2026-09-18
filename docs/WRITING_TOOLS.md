# Spelling & Grammar and Quick Fix

This slice provides an editable native grammar/spelling checker and a real macOS text Service.
The Service returns corrected text to the editor that supplied the selection. It is distinct from
opening the launcher with an external selection: that direct launcher selection acquisition and
replacement behavior remains a gap in video row 59. No universal editor support is claimed.

## Review checker

Open **Spelling & Grammar** or **Check Spelling & Grammar**, type or explicitly paste up to 16 KiB,
choose an installed language or Automatic, and choose **Check Text**. The native engine returns
issues, explanations, and replacements where available. **Use Automatic Suggestions** applies only
eligible native autocorrections and grammar issues with a single offered replacement. Overlapping
ranges or truncated reports require review. Successive individual choices are retained and recomputed against the immutable original. Conflicting
choices fail without discarding accepted edits. **Restore Original** clears accepted choices and is required
before suggestions may overwrite manually edited output. Automatic suggestions preserve earlier explicit choices.
The result is editable, and **Copy Result** explicitly copies at most 64 KiB. Input edits, cancellation,
and session teardown invalidate pending results. No correction runs on launch or as the person types.

macOS supplies the spelling and grammar engine through `NSSpellChecker.requestChecking`. The request
uses spelling, grammar, and correction types, with macOS 27's full-grammar-results option. Checking
runs in the background; the completion may arrive in any context. Native results are converted into
Sendable values and delivered on the main run loop. Every request uses a unique spell document tag,
which is closed after completion or cancellation. The native API has no public per-request cancel
method; Commandly drops the completion and closes its tag, so late results cannot enter another view.
Language and grammar coverage depend on installed macOS spelling services and settings. Some issues
supply only explanations, with no automatic correction. Commandly has no network or BYOK dependency
in this workflow; it does not claim to control third-party spelling services configured by the user.

## In-place Service

In another app, select text in an editable field and invoke **Services → Quick Fix Selection Locally**.
That explicit command authorizes automatic eligible local corrections to that selection. A brief native
progress panel offers Cancel and Escape. The service receives only its request-specific pasteboard,
never `NSPasteboard.general`; the host's Services requestor owns selection replacement and native Undo
where supported. It does not read an Accessibility tree, synthesize keys, move the host selection,
replace an entire text field, or silently upload the selection to an AI provider.

The native Services handler is synchronous. Commandly uses a short AppKit modal event loop while the
spelling API works asynchronously: no blocking spelling call, semaphore, `Task.sleep`, or main-thread
file I/O. A timer registered in the modal run-loop mode ends the operation after 8 seconds; the advertised
system timeout is 15 seconds. The result winner also checks the monotonic deadline, and the final
pasteboard commit checks it again. Cancel, timeout, malformed/overlapping results, or an altered
pasteboard return no correction. Late native callbacks are inert. Commandly windows are temporarily
modal during this short operation; the service never waits indefinitely for a review decision.

Before the progress panel appears, Commandly captures only the frontmost application's metadata and
retains a best-effort focus restoration closure. It restores that app only if Commandly is still
frontmost and the original process is alive. This is not authority to inspect or write that app's AX
fields. The exact selection authority remains the native Services transaction. Shared system pasteboard names (general, find, font, ruler, and drag) are rejected before any text read. Each commit verifies
the named pasteboard identity, change count, and original text before writing; a changed request fails
closed. Unchanged text passes the same identity/deadline checks but never writes a replacement, avoiding unnecessary rich-text changes or Undo entries. Errors returned through the service selector are fixed strings because macOS may log them.

For a shortcut, enable the service and assign an unused key in **System Settings → Keyboard → Keyboard
Shortcuts → Services → Text**. The launcher provides a discoverable **Quick Fix in Other Apps** instruction
tool; it does not pretend this command captures an external selection. Run Commandly from Applications
and reopen the editor if a newly registered Service is missing. Editors without text Services use the
review checker and Copy Result. Host insertion, rich-text preservation, and Undo need native acceptance
checks in each supported editor; plain-text Service availability does not prove all editors implement them.

## Integration contract

- Register `WritingToolsApplication(services:)`, using `WritingToolsApplicationServices.live` in production
  and `.inMemory` in fixtures. `.live` constructs the native checker but does not run a check or read text.
- Retain `NativeWritingServiceProvider(checker: services.checker)` and set `NSApp.servicesProvider` only
  after the app is ready. AppKit supports one provider object, so compose future services into that same
  provider rather than overwriting it. No registration occurs from a view's initializer.
- Add one `NSServices` Info.plist entry with `NSMessage = quickFixSelection`, `NSPortName = Commandly`,
  `NSMenuItem = { default = Quick Fix Selection Locally }`, `NSSendTypes` and `NSReturnTypes` containing
  `public.utf8-plain-text`, `NSRequiredContext = { NSServiceCategory = public.text }`, `NSRestricted = false`,
  `NSTimeout = 15000` (string), and a description explaining that invocation applies eligible local
  corrections directly. No default service key is imposed; user assignment avoids editor conflicts.
- No entitlements, privacy usage strings, Accessibility grants, global clipboard reads, or network grants
  are added. Keep App Sandbox enabled and the rejected Window Switcher boundary intact.

`Infrastructure/WritingTools.swift` owns bounded Sendable reports/ranges and the correction policy.
`NativeWritingResultParser` interprets native ranges: grammar detail offsets are relative to the enclosing
sentence. It limits results and suggestions and collapses duplicate spelling/autocorrection issues.
`WritingServiceTransaction` and `WritingInlineOperation` enforce request and deadline identity independently
of AppKit windows. `NativeWritingInlineProgress` owns the bounded native modal loop. The view model owns
only session input, report, and editable result, and requests explicit Copy through the existing port.

## Verification

Fixtures cover UTF-16 emoji/range preservation, overlapping and duplicate IDs, truncated reports, bounds,
unsupported suggestions, native grammar offset parsing, explanation-only issues, request-only pasteboard
writes, changed requests, cancellation/deadline races, late callbacks, explicit checker activation,
input edits, copied reviewed text, and distinct review/help command metadata. Tests do not access a real
clipboard, user's text, Keychain, network, permissions, or native external editors. Native parser tests
construct `NSTextCheckingResult` values; they do not invoke a real spell server.

Isolated compile checks precede publication. The root task owns shared Xcode builds, all tests, Services
registration validation, and synthetic TextEdit selection/Undo/progress acceptance. Do not mark video
row 59 complete solely because this alternate native Services route works: direct launcher-selected-text
capture and the reference's exact inline presentation remain unimplemented.

## Generated native UI fixture

DEBUG builds may inject `WritingToolsDebugFixture.services`. Enter exactly `🙂 This are teh sample sentence.`
and choose Check Text. The fixture returns two explicitly labeled generated suggestions; Use Automatic
Suggestions produces `🙂 This is the sample sentence.` Copy Result writes only an in-memory pasteboard.
Other text is rejected as a malformed fixture request, and unsupported languages fail explicitly. No real
spelling engine, general clipboard, current selection, permission, Keychain, file, or network is used.
These deterministic suggestions validate the UI and cannot establish native spelling quality or Services
host behavior. The checker header has a heading trait, its editable text follows the app's text scale,
and its help instructions scroll at larger sizes. Focus is requested after editor attachment and canceled
if the session disappears or switches to help before that request runs.

## Primary API references

- [Apple Services provider guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html)
- [Apple Services requestor/selection guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/using.html)
- [Apple Services properties and timeouts](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)
- [Stopping an AppKit modal loop](https://developer.apple.com/documentation/appkit/nsapplication/stopmodal()) supports a timer callback on current macOS; the timer is registered in the modal run-loop mode.
- [NSSpellChecker](https://developer.apple.com/documentation/appkit/nsspellchecker), plus the installed macOS 27
  `NSSpellChecker.h`, `NSSpellServer.h`, and `NSTextCheckingResult.h` ownership/threading/range comments.
- macOS 27 `AXAttributeConstants.h` documents `AXSelectedText` as read-only and `AXSelectedTextRange` as writable.
  This is why there is no assumed general AX selected-text write fallback in this slice.
