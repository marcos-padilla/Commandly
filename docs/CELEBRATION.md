# Confetti celebration

Confetti is a registered launcher application (`celebration.confetti`) with one stable tool,
Celebrate with Confetti (`celebration.confetti.play`). Searching or selecting the result does
not animate anything. Opening it presents a normal launcher session and plays one burst when the
surface appears. Return or Celebrate Again replaces the current burst; Done, Back, or Escape
returns to the launcher. It creates no additional windows and never brings itself forward later.

The feature is owned by `Scenes/Launcher/Commands/Celebration`. `CelebrationBurst` supplies a
finite explicit timeline of 97 dates over 3.2 seconds at 30 frames per second. One SwiftUI Canvas
draws 72 small, deterministic geometric pieces with no per-particle views. The final frame contains
no moving pieces, and the timeline has no subsequent scheduled dates. Replaying replaces the
timeline identity. Stopping the session or removing the view clears the burst and removes the
timeline. There are no repeating timers, tasks, background workers, or particle allocations per
frame beyond the bounded drawing values.

Reduce Motion uses a stationary 20-piece arrangement and creates no TimelineView. Turning the
setting on discards the active burst immediately; turning it off does not start a new one until
the user replays. Decorative particles and the sparkle symbol are hidden from VoiceOver. The
title remains a header, controls have textual labels, Return is the default replay action, and
Escape is the cancel action. The surface uses Commandly typography and spacing on the shared
neutral canvas; the small decorative confetti palette has no status or navigation meaning.

No permission, network connection, data persistence, sound, clipboard access, or logging is added.
The artwork is original geometry and SF Symbols; it uses no third-party or competitor assets.
Onboarding is unchanged.

`CelebrationApplicationTests` covers finite schedule length and particle bounds, replacing a
burst on replay, stopping and stale callback behavior, Reduce Motion transitions, Escape/navigation,
tool registration, unknown-tool rejection, and isolated session cleanup. These model tests do not
claim native rendering, VoiceOver, or frame-rate measurement; those require a runtime check.

SwiftUI's finite schedule behavior follows Apple's
[ExplicitTimelineSchedule documentation](https://developer.apple.com/documentation/SwiftUI/ExplicitTimelineSchedule).
