# Window Layouts companion boundary

Every built-in preset and saved custom layout is an individual searchable command with its own
shortcut assignment. New custom layouts refresh the command catalog immediately; deleting one
removes its command without affecting other tools. Direct shortcuts apply the current saved
rectangle, so stale arguments cannot apply a removed layout. The custom catalog is bounded to
256 entries and uses the same backing store as the editor.

The existing 58 presets and user-created normalized rectangles use a typed System Companion operation. Custom layout identifiers, names, storage format and keyboard browser are preserved. The sandboxed app does not use Accessibility to control another app.

The authenticated bound integration has been source-reviewed and enabled in composition. Check Connection creates an authenticated bound session; Window Layouts remains off until its explicit System Integration toggle is enabled. The toggle remembers only one external application identity. It does not request or grant Accessibility. Applying a layout checks the companion's existing grant and gives an Accessibility Settings recovery message if needed.

Apply captures the remembered external app's **currently focused window at Apply time**, not its window when the launcher appeared. The helper observes app activation while the capability is enabled and connected. It retains PID, exact kernel process birth time, bundle identity, executable identity and a generation. The kernel birth stamp supports apps such as login-started Finder for which LaunchServices has no launch date; no PID-only fallback exists.

A captured window receives a random, single-use, session-bound handle with a three-second expiry. Focus/process/display changes, release, disable, cancellation, lock/session loss, permission failure and disconnection invalidate targets. All AX work runs on a dedicated worker queue with bounded per-message timeouts, validation immediately before writes, and no arbitrary attribute or action names. Only finite bounded geometry crosses the channel. No window title, target identity, screen coordinates, document content or native object is returned or persisted.

Resize and move are separate native writes. Receipts distinguish exact success, constrained bounds, unavailable readback, partial mutation, confirmed refusal and uncertain delivery. A timeout can occur after a target-side change: the app tells the user to inspect the window before trying another layout. It does not silently retry or claim the window stayed unchanged.

The listener creates the inert feature controller only from an OS-authenticated bind invocation and its kernel peer PID. Both client bound-channel allowlists and the helper factory use the same reviewed composition gate. The named transport remains metadata-only. Existing code-signing requirements, user/audit session validation, deadlines, replay limits and terminal channel invalidation remain mandatory.

The main app cancels the pending UI invocation and releases targets when the launcher closes or Commandly resigns active. Public session-resign and screen-sleep notifications revoke helper state; exact screen-lock delivery remains a native acceptance item, not a guarantee inferred from these notifications. No private lock notifications, private Spaces APIs, shell execution or AppleScript are used.

Isolated compilation and fake tests do not prove native Accessibility grants, registration, lock delivery, app compatibility or actual window mutation. Native acceptance requires an explicit user grant and intentional window tests. No native permission or helper activation is performed by the source integration.
