# Display Resolution

Display Resolution opens an independent native window after an explicit launcher action. Its service
constructors do not scan displays, prompt for permissions, change modes, or install observers. Opening
the chooser reads connected displays through CoreGraphics and their names through a short AppKit hop.
The native adapter retains all CG display-mode objects on its actor executor; UI and domain boundaries
receive only bounded, Sendable values.

Choose an active, non-mirrored display and a mode, then choose **Apply Preview**. The mode list includes
logical dimensions, pixel dimensions/HiDPI, and refresh rate when reported. A zero native refresh value
is shown as unknown, not as a fabricated fixed refresh rate. Modes below 640 × 480 remain listed but
cannot be previewed, so the confirmation controls can remain readable. Mirrored/inactive displays
direct the person to System Settings, because Quartz can change other members of a mirroring set.
The list and controls support keyboard navigation and accessible labels; content follows the shared
AuxiliaryWindowAppearance text size, and the chooser body scrolls independently of its confirmation
buttons. A topology change clamps the native window to an available visible screen without extending
the preview deadline or automatically stealing foreground focus.

## Configuration scopes and deadline

- Preview is a `CGBeginDisplayConfiguration` / `CGConfigureDisplayWithDisplayMode` /
  `CGCompleteDisplayConfiguration(..., .forAppOnly)` transaction. No mode mutation occurs from
  opening, selecting, resizing the window, or reading available modes.
- The decision deadline is 15 seconds, measured using a continuous monotonic clock from the start
  of Apply. A timer updates the countdown and requests automatic revert at the deadline. Wake and
  display-change notifications also recheck the deadline. Reopening the chooser, changing screens,
  or a wall-clock adjustment cannot extend it. Keep is rejected at or after the exact deadline.
- **Keep for This Session** is an explicit decision before that deadline. The adapter revalidates
  the exact preview then requests `.forSession` for the selected mode. It never uses `.permanently`.
  Once Keep is accepted, closing waits for that decision rather than silently undoing it.
- Native configuration calls are synchronous WindowServer operations on the driver actor and cannot
  be forcibly interrupted. Cancellation/timeout during an in-flight call records a required revert;
  the coordinator performs it when that call returns. The UI never reopens a passed confirmation
  window. A hung OS call or unresponsive process cannot provide a hard real-time rollback guarantee.
- Apple documents app-only configuration removal at app termination and session configuration removal
  at logout. Its APIs offer the scopes used here, but successful promotion of a running app-only
  preview to a session mode and persistence after quitting Commandly remain native acceptance checks.

The adapter cancels an uncommitted configuration after setup failure. Complete consumes the config
reference even if it fails, so the adapter never cancels that consumed reference. The driver re-reads
native configuration after every successful operation instead of treating a success code as proof that
the requested mode was honored.

## Exact identity and restoration

A catalog and every display/mode choice have new session-only UUID tokens. Internal hardware identity
includes the current CG display ID, public ColorSync UUID, and vendor/model/serial metadata; none is
logged or persisted. A mode fingerprint includes its native I/O mode ID, logical and pixel dimensions,
refresh rate, flags, and desktop usability. Equal-looking resolutions with different pixel density or
refresh rates are distinct. The native driver re-enumerates current mode objects and requires the
expected topology, current modes, origins, and available mode fingerprints immediately before writing.
It never applies an old retained mode object to a new configuration.

The transaction service retains the original exact mode and recovery authority before the write.
If macOS substitutes a different mode, the service does not offer it as the selected preview; recovery
uses the observed result of that operation. If another app subsequently changes the selected mode,
Keep fails and Revert leaves that newer choice untouched, reporting that the original was not restored.
Restoration never chooses an approximate mode and never calls the global
`CGRestorePermanentDisplayConfiguration` function.

Preview rollback normally uses app-lifetime scope. Once Keep has attempted a login-session promotion,
rollback uses login-session scope too: an app-only rollback could otherwise reveal the failed session
choice again when Commandly exits. A disconnected/replaced display, unavailable exact original mode,
or failed restoration retains recovery state and exposes **Retry Revert** and **System Settings**.
The latter opens the System Settings app through its registered bundle; the person chooses Displays.
No undocumented settings URL or shell command is required.

The confirmation window and coordinator are independent of the launcher. Closing the confirmation or
pressing Escape while a preview is pending requests restoration; an in-flight operation is awaited.
Failed restoration keeps the recovery controls visible. Quitting participates in the app's deferred
termination handshake. If restoration fails, the first quit is canceled and an explicit recovery quit
is offered. For app-only previews, macOS normally removes the override at process exit, but that is
not a guarantee of the exact pre-preview mode. If a session promotion was attempted and recovery
failed, even that exit fallback may retain the mode until logout; the recovery UI says so explicitly.
No settings are written to disk, and no new permission or entitlement is required by this feature.

## Integration

1. Construct and retain one `DisplayResolutionApplicationServices.live(appearance:)` in AppRuntime.
   Supply the runtime's shared `AuxiliaryWindowAppearance`. Use `.inMemory(appearance:)` in isolated
   UI fixtures; it exposes a generated display with HiDPI, standard-pixel, and deliberately tiny modes.
   Its Apply/Keep/Revert change only actor memory, and its Settings/Quit callbacks perform no action.
2. Register `DisplayResolutionApplication(services:)`, ID `system.display-resolution`. The launcher
   action dismisses the launcher and opens the coordinator-owned window. No application-specific
   branch is needed in the launcher shell.
3. Extend the shared termination gate with `requiresTerminationReview`,
   `requestCloseForTermination(completion:)`, and `cancelPendingTermination()` on the retained coordinator.
   Order preparation as recording review → display restoration → note review → recording commit.
   Wait for the display's Boolean reply; a `false` reply keeps the app open for recovery. Include
   `requiresTerminationReview` in the final current-state check in the same actor turn as AppKit's reply.
   A later explicit recovery quit waives exact rollback for that attempt only, so this property becomes
   false even while `hasPendingChange` truthfully remains true. If any feature cancels termination,
   call `cancelPendingTermination()` to withdraw that waiver and any pending reply. The call replies
   false at most once and does not cancel an already-requested display restoration, close the window,
   or stop display observation. A new Apply resets any recovery-quit waiver.
4. Do not discard the runtime coordinator or cancel its mutation task from launcher teardown.
   Its own window close/quit/timeout transitions perform and verify recovery. When the process is
   actually terminating, CG's configuration scope is the final app-only cleanup boundary.

## Verification

Eighteen service/coordinator tests have run successfully in a separate temporary Swift package using
the actual new service/coordinator sources, generated hardware, and a controllable monotonic clock.
They cover identity, stale catalogs, pixel/refresh distinctions, substitution, external choices,
disconnection/replacement, failure/retry, session-scope rollback, timeout/close during an in-flight
apply, exact deadline rejection, reopen behavior, and the termination handshake including cancellation during Apply and withdrawal of an explicit recovery-quit waiver. An application
registration test is included for explicit opening/discovery without native windows or display writes;
its execution awaits the coordinated Xcode run.
No test changes this Mac's resolution, reads user files, prompts for permission, or uses a real display
configuration driver. Full Xcode verification and native acceptance are owned by the root task.

The shipping sandbox/signing configuration, actual display discovery, full-screen rejection,
multi-monitor confirmation visibility, timed real rollback, unplug/replug recovery, and Keep followed
by quitting/relaunching remain unverified until exercised on controlled hardware with explicit user
authorization. Fixture UI acceptance proves presentation and state transitions, not an actual display
mode mutation or session persistence.

## Primary references

- [CGCompleteDisplayConfiguration](https://developer.apple.com/documentation/coregraphics/cgcompletedisplayconfiguration(_:_:))
- [CGConfigureDisplayWithDisplayMode](https://developer.apple.com/documentation/coregraphics/cgconfiguredisplaywithdisplaymode(_:_:_:_:))
- [CGDisplayCopyAllDisplayModes](https://developer.apple.com/documentation/coregraphics/cgdisplaycopyalldisplaymodes(_:_:))
- Installed macOS 27 public SDK headers: `CGDisplayConfiguration.h` defines scope lifetime,
  consumed configuration ownership, mirroring effects, and callback constraints; `CGDirectDisplay.h`
  defines point/pixel dimensions, refresh rate and mode ownership; `ColorSyncDevice.h` declares the
  public display-ID/UUID conversion used for transient hardware identity.
