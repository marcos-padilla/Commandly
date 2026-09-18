# Configured keyboard triggers

Keyboard triggers implement the optional companion boundary in ADR-0011. They are off at launch;
opening Settings, opening setup, checking a connection, and loading saved bindings do not create an
event tap. The app stays sandboxed. Only the authenticated, peer-instance-bound action endpoint can
configure the helper. The named metadata endpoint rejects these operations. The separate compiled
`CompanionKeyboardTriggerReleaseGate` remains closed in the staged slice pending root review.

Settings → System Integration contains a configuration section for:

- Caps Lock held with another key as Hyper (Control, Option, Shift, Command). An optional short,
  solitary tap (at most 250 ms) preserves Caps Lock. Long solitary holds do not toggle Caps Lock.
- A configured function key, or a printable single key in a known non-editable context, dispatching
  an existing registered argument-free command or saved file Quicklink. Hyper bindings work in text
  contexts. Unknown/editable fields pass ordinary printable single keys through.
- Two clean taps of a selected left/right modifier within 350 ms opening a saved file Quicklink.
  Both ordinary modifier events pass through. A chord or long press cancels the sequence.
- Explicitly enabled literal snippet/emoji keyword expansion. Keywords are 2–32 ASCII characters
  with a punctuation prefix and match at an observed word boundary, followed by Space/Return/Tab.
  The existing Library owns snippet/emoji bodies. Dynamic templates, clipboard placeholders and
  named inputs require the interactive Library flow. Expansion is supported only by editable AX
  fields exposing public selected-range, bounded string-for-range, and selected-text setter APIs.

Configuration edits require Stop first. The JSON preferences store holds bindings and item IDs,
not a persisted enabled flag, typed input or duplicated snippet bodies. Native setup's visible
“Review Keyboard Access” explanation is the only Input Monitoring/Accessibility permission request.
Configure only preflights existing grants. The Settings UI and tap never prompt automatically.

## Input and mutation boundary

CGEvent Caps Lock flags represent the processed lock toggle and are unsuitable as physical down/up
signals. The helper uses public IOHIDManager input-value matching restricted to keyboard Caps Lock
usage, without device seizure, plus public IOHID modifier-lock state access. A session CG event tap
modifies the flags of actual key events; it does not synthesize modifier keydowns. Release/reset posts
one marked flags notification using physical modifier state. No persistent system key mapping,
private API, shell, AppleScript, root service, or virtual keyboard driver is used.

One dedicated run-loop thread owns tap/HID/AX objects. A synchronous lock-backed authorization lease
is checked before interception and each expansion mutation. Disconnect revokes it before asynchronous
teardown. Secure Input, a secure focused field, permission loss, input source change, session resign,
sleep/wake, a removed keyboard, event-tap disablement, or a five-second missing physical Caps release
stops input handling and resets modifiers. Re-enable is explicit. Stop waits for the old thread to
finish before a replacement tap starts. The helper's original five-minute authenticated session and
256-request replay ledger remain bounded; expiry requires an explicit connection check and enable.

Unrelated key data is passed through and never retained, logged or sent over IPC. Expansion retains
only a prefix of a configured keyword, at most 32 ASCII characters; focus/mouse/shortcut/secure/input
source boundaries clear it. It never reads the whole field. At the delimiter it checks the current
non-secure focused element, caret, exact keyword range and preceding boundary, selects that range,
rechecks identity/range/content, and uses the public selected-text setter. Refused setters attempt to
restore only that same range. AX cannot make separate range/text setters atomic; unsupported,
changing or unresponsive hosts may refuse expansion. Host Undo behavior requires native acceptance.
There is no clipboard, synthetic typing/backspace, AXValue replacement, or AI fallback.

The helper queues at most 32 opaque binding UUID activations, scoped to a configuration revision.
The app polls only the authenticated bound channel, validates revisions and at-most-once IDs, then
uses the existing typed shared command executor or existing validated Quicklink opener. Overload
stops the tap instead of replaying an unbounded command backlog. Expansion bodies cross to the
verified helper only on explicit enable; key input, active suffixes and native field identities do not.

## Verification and remaining native work

The isolated package compiles the real Infrastructure/SystemCompanionKit graph, native driver,
helper executable, and new Settings/model/preferences code with Swift 6 strict concurrency and
warnings as errors. Eight focused tests cover Caps tap/chord/hold/reset, typing pass-through,
repeat/up suppression, clean double taps, suffix minimization/reset, configuration bounds,
synchronous revocation, metadata rejection, authenticated session routing and explicit opt-in.
App target integration patches still require the root aggregate compile/verify.

No event tap, input observation, permission request, live AX mutation, helper registration or signed
native acceptance was run for this slice. Supported hardware, HID/CG ordering, protected contexts,
layout/input-method behavior, repeat handling, reconnect/stop and host Undo remain native gates.
Do not mark video rows 19/20/37/38 or automatic expansion as native-accepted from these unit results.

Public API references: [CGEvent tap creation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[IOHIDManager](https://developer.apple.com/documentation/iokit/iohidmanager),
and installed macOS SDK IOKit `IOHIDManager.h`, `IOHIDLib.h`, `IOHIDParameter.h`, Carbon
`TextInputSources.h`, and ApplicationServices `AXUIElement.h`.
