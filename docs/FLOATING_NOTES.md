# Floating Quick Notes

A Floating Quick Note is a small, independent macOS editor backed by the existing Productivity
Library. It stays available when the launcher closes or another app takes focus. It is an original
Commandly desktop surface; this work does not implement or stand in for the still-open iPhone notes
requirement from the reference video.

## Behavior

- **New Floating Note** opens a blank note with focus in its plain-text body. A title is optional;
  saving an untitled note uses the first line. Existing Quick Notes can open in this surface.
- **Save** (`⌘S`) writes only this note to the local library. **Save & Close** (`⌘Return`) saves and
  closes the window. Plain Return adds a new line. Native editing supplies selection, undo, copy,
  paste, and spelling behavior; Commandly never copies or reads the clipboard implicitly.
- The note initially stays above ordinary windows. **Keep note on top** toggles its window level;
  turning it off restores ordinary window ordering. Save/status updates never activate a window.
- Opening a note already being edited focuses its existing window without replacing the draft.
  Different notes have separate windows and undo/editing state. New windows cascade on the active
  display and can move or resize normally. There is no automatic reopening, focus timer, or global
  mouse/keyboard monitor owned by this feature.
- Escape, `⌘W`, and the title-bar close button request a safe close. An unsaved draft offers
  **Save & Close**, **Discard Changes**, and **Keep Editing**. Closing a saved note never deletes it
  from the library. A blank untouched window closes without creating an empty library item.
- Application termination must use the coordinator's close-all handshake. Cancelling any close or
  failing to save cancels termination and leaves the draft available. Pending saves finish before
  the close decision; late edits remain dirty rather than being mistaken for saved content.
  Opening or focusing a note during the quit handshake cancels only the quit-owned close prompts
  and deferred closes. Existing authorized saves and explicit Save & Close requests continue.
- A concurrent edit or deletion of the same note is a recoverable conflict. The draft remains in
  its window; **Save as Copy** (`⌘Shift-S` in the conflict state) keeps it under a fresh library
  identity alongside the newer saved version. Unrelated note, snippet, tag, and Quicklink edits
  survive each save. The main library editor similarly offers **Save as New Item** on conflict.

## Ownership and persistence

`Services/ProductivityLibrary/ProductivityLibraryMutation.swift` defines create, expected-version
replace, and expected-version delete transactions. `ProductivityLibraryPersisting.applyChanges`
returns the resulting library. JSON and in-memory adapters apply each transaction without an actor
suspension between reading, checking versions, and writing. JSON remains version 2, preserving the
existing version-1 migration, timestamps, item kinds, tags, and template text. No separate note
file format or content copy is introduced.

All live library editors and the floating-note coordinator must receive the **same persistence
actor** from the runtime. Atomic JSON replacement protects writes; this protocol does not promise
cross-process coordination for independent processes manually writing the same file. The older
whole-list `saveItems` entry point remains for fixtures/import initialization; interactive editors
use item transactions. A conflict in any transaction member leaves the entire stored list intact.

`Scenes/FloatingNotes/FloatingNoteModel.swift` owns one editable draft, its expected saved version,
validation, save result, and safe-close state on MainActor. `FloatingNoteCoordinator` retains
independent models/windows outside launcher sessions and deduplicates explicit note opening.
`FloatingNoteWindowController` adapts the fakeable presentation port to a resizable `NSWindow` with
normal title bar, native edited indicator, level toggle and scoped keyboard handling. The SwiftUI
surface and native `NSTextView` wrapper live beside them; business/persistence logic stays in the
model and service actor.

The runtime injects `FloatingNotePresenting` into the Productivity Library, registers the
new tool/open action, and exposes `savedRevision` to refresh an idle library view. It does not replace an
in-progress library draft during a background refresh. The library model retains its original edit
version even if its list refreshes, so that it still detects competing edits.

## Privacy and accessibility

Notes, titles, tags, and errors containing no private values stay within local app memory and the
existing private Application Support library. There are no network calls, device permissions,
automatic clipboard operations, exported temporary files, or note-content logging. Drafts have no
background autosave: the native edited indicator and status distinguish unsaved work. Saving is
explicit, and safe close/quit decisions prevent silent draft loss.

New notes are bounded to a 200-character title and 1 MiB UTF-8 body; oversized insertion is rejected
with a visible message. Existing larger library text can be shortened, but must meet these bounds
before this editor saves it. Tags are preserved without adding another metadata editor.

Window/title/body/save controls have native or explicit accessibility labels and stable identifiers.
The body receives initial focus at actual AppKit window attachment; an already-backgrounded window
cannot reclaim focus from that deferred attachment. Input-method composition keeps normal Escape
behavior. The accessibility container preserves child controls. Semantic macOS colors and scalable
Commandly text styles adapt to light/dark appearance. The runtime shares its observable text-size
preference with every floating note, including already-open editors, without replacing the model or
reclaiming focus. No custom animation or transparency is needed.
Native Full Keyboard Access, VoiceOver order, scaling, Spaces, and actual focus/undo/close behavior
still require live acceptance on the built app.

## Verification

New automated suites:

- `FloatingNoteIntegrationTests`: dedicated tool and saved-note handoff use the shared presenter,
  dismiss the launcher first, preserve note identity, and defer library refresh until a draft closes.
- `ProductivityLibraryMutationTests`: independent writes on JSON and memory stores preserve
  unrelated notes/template metadata; stale versions and partially invalid transactions cannot
  write; library-editor conflicts retain drafts and save as new; deletion checks the version that
  was actually confirmed.
- `FloatingNoteTests`: explicit persistence, automatic title, reopen/close behavior, discard,
  save failure, edits during suspended save, conflict copy recovery, and size validation.
- `FloatingNoteCoordinatorTests`: lazy window creation, same-note deduplication, independent
  windows and writes, closing without deletion, cancellable multi-window quit, clearing a cancelled
  quit prompt/deferred close, and preserving an earlier explicit Save & Close request.
- Existing `ProductivityLibraryTests` and `ProductivityLibraryTemplateTests` remain regression
  coverage for CRUD, migration, cancellation, tags, Quicklinks, and templates.

Tests inject stores/windows and use temporary generated JSON fixtures; they never open real windows
or access the real library/clipboard. Run the five app suites above, then `make verify`. This
implementation document does not itself claim the build, tests, native focus, or app-quit flow passed.

The native adapter follows Apple's [NSWindow documentation](https://developer.apple.com/documentation/appkit/nswindow)
and [window level API](https://developer.apple.com/documentation/appkit/nswindow/level). The coordinator's
close decision is intended for [applicationShouldTerminate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)).
