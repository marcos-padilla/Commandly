# Slack Custom Emoji

Video row 12 (0:47) has a dedicated original Commandly application, `media.slack-emoji`, and a
`media.slack-emoji.tool.open` entry point. It connects a user's own internal Slack bot app, refreshes
one selected workspace's custom emoji, searches names and aliases locally, and explicitly copies
a Slack shortcode or copies/saves original PNG, JPEG, or GIF data. Integration and native acceptance
must be completed before marking the video row verified.

## Setup and authority

The user creates and installs a dedicated internal app in their own Slack workspace and supplies
its bot access token. Workspace administrator approval may be needed. Commandly does not create an
account or app, install or approve an app, accept terms, run a distributed OAuth redirect flow, or
automatically rotate tokens. User, browser-session, and app-level tokens are refused. Rotating bot
access tokens can be entered, but must be replaced when they expire.

Check & Connect calls `auth.test` followed by `emoji.list`, using HTTPS POST with an Authorization
bearer header and no query parameters. Both responses must confirm exactly `emoji:read` in
`X-OAuth-Scopes`; missing evidence and additional scopes fail closed. The identity response must
include a bot, workspace ID, name, supported Slack workspace URL, and a valid optional Enterprise ID.
An invalid, denied, expired, malformed, oversized, or unverified response never saves the token.

One bounded, versioned record in the existing `SecureStoring` Keychain adapter holds up to eight
independent connections under `slack-custom-emoji.connections.v1`. Workspace metadata and tokens
stay together; no copy is written to UserDefaults. Replace Token revalidates the same workspace ID
and assigns a new local revision. It can explicitly accept an updated bot, workspace domain, or
Enterprise membership. Refresh rejects changes to any of these identity fields before `emoji.list`.
Remove Connection deletes local access without revoking or uninstalling the Slack app.

Cancel Checking and Escape cancel the current operation. If a secure write has already started,
the session retains and awaits it, then reloads the committed connection state. A late write cannot
reopen a retired sheet or publish stale success. Closing/reopening a launcher session follows the
same settlement boundary. Token input is cleared on connect, cancellation, Done, and session stop.
The shared service also owns cancellable connection-read waiters: a fresh launcher model waits for
a retired model's write to finish before reading saved connections. Cancelling one reader removes
only that waiter. Every mutation exit wakes surviving readers, including failed writes, and a
generation check retries reads that overlap another mutation.

Primary provider references checked 2026-09-17:

- [emoji.list](https://docs.slack.dev/reference/methods/emoji.list/) defines custom emoji, aliases,
  the `emoji:read` bot scope, and its rate-limit behavior.
- [auth.test](https://docs.slack.dev/reference/methods/auth.test/) defines returned bot/workspace
  identity and optional Enterprise identity.
- [Slack Web API](https://docs.slack.dev/apis/web-api/) documents POST form requests and bearer
  authentication; [OAuth scope reporting](https://docs.slack.dev/authentication/installing-with-oauth/)
  documents the granted-scope response header.
- [Tokens](https://docs.slack.dev/authentication/tokens/) and
  [token rotation](https://docs.slack.dev/authentication/using-token-rotation/) describe token types
  and expiration. This implementation uses the supplied bot token, without a refresh-token flow.

## Session data and network boundary

Opening the tool reads saved connections only. Refresh Emoji explicitly fetches the selected
workspace's inventory. Typing subsequently filters its names and resolved alias targets on the
service actor, with cancellation, exact-name priority, and an honest 300-result visible cap.
Queries never reach Slack. Names remain distinct: copying an alias produces its own `:alias:`.
Missing targets, cycles, chains deeper than 64 steps, and unsupported image URLs stay visible with
an explanation. The full response must fit 4 MiB and 20,000 names; a partial inventory is never
presented as complete. Catalogs, names, aliases, and previews are memory-only and released at exit.

Selecting an image fetches only that selection. Each media request is freshly constructed without
Authorization, cookies, or URL credentials. The ephemeral transport has no URL cache, cookie store,
credential store, or automatic redirects. Its media policy permits only HTTPS PNG/JPEG/GIF paths
at the verified workspace's `/emoji/` host, Slack's documented legacy `my.slack.com/emoji/` host,
or `emoji.slack-edge.com` paths beginning with the verified workspace or Enterprise ID. Paths and
query strings from Slack remain intact. Three manually validated redirects are allowed; foreign
hosts, different workspace paths, fragments, credentials, and nonstandard ports are refused.
This is a conservative application policy, not a claim that every Slack deployment uses these hosts.
Legacy addresses that require browser cookies or private authorization remain unavailable.

Responses are bounded by declared and received size: 128 KiB for identity, 4 MiB for the inventory,
and 8 MiB per image. Cancellations and rejected responses cancel the URLSession task. HTTP 429 and
Slack rate-limit errors establish a local retry deadline; the tool never automatically retries.
Every result remains tied to a current credential revision, catalog ID, and exact catalog item.
Connection changes cancel work and invalidate catalog authority; late results are rejected.

Slack receives the supplied token on its two API methods, requested emoji media URLs, and ordinary
network metadata such as the client IP. Commandly never logs tokens, workspace names, queries,
emoji data, response bodies, or URLs. No message, channel, user-profile, or file API is called.
There is no AI integration, persistent emoji cache, search/history database, posting, or automatic
paste. Explicit copies may be captured by the separate Clipboard History feature if enabled.
Existing network-client and user-selected-file entitlements suffice; no new TCC prompt is added.

## Image, export, and accessibility boundary

ImageIO inspection and preview decoding run on an actor. Images must be complete PNG/JPEG/GIF
sources, at most 8 MiB, at most 8,192 pixels per dimension, and at most 16,777,216 pixels per frame.
GIFs permit at most 1,000 original frames. Animated preview reuses the existing bounded
`GIFAnimationDecoder` (400 frames, 360-pixel thumbnails, 48 MiB decoded storage), while static
previews retain at most 4 MiB of pixels. Original media remains available for explicit export when
only the stricter preview budget is exceeded. Source metadata and original bytes are preserved;
this feature does not edit or sanitize the source image.

Return copies `:name:` as text. Command–Shift–C copies validated original bytes under their actual
image type; GIF animation is preserved. Save Image chooses the matching native file type through
NSSavePanel and reuses `NativeGIFFileWriter` for coordinated, scoped, atomic writes. Cancellation
closes the Save panel; the writer revalidates the exact destination and reports cleanup failure
separately if the file already committed. There is no implicit sharing or Slack message action.

The original SwiftUI surface has native search, workspace picker, result list, connection sheet,
secure token field, and Save controls. Arrow keys select results, Return copies the selected name,
and Escape cancels the nearest operation before Back leaves. The connection sheet scrolls beneath
its fixed Done/Cancel control. Rows expose both the shortcode and alias/error meaning to VoiceOver.
Preview playback can be paused; Reduce Motion displays a still frame and disables playback actions.
Queries and workspace changes clear the prior selection before an immediate Return can copy it.
Native focus, VoiceOver, compact density, large text, and light/dark review remain acceptance gates.

## Verification and remaining acceptance

The isolated Swift 6 build uses MainActor default isolation, complete strict concurrency, and the
app's upcoming isolation features. It passed 30 tests in six suites, including independent
workspace URL, bot, team, and Enterprise identity-drift cases; precommit cancellation; cancellation
after a memory-only secure write starts; fresh-model reads during successful/failed retired writes;
independent cancellation of mutation waiters; local search; stale selections; alias cycles; scope
refusal; credential-free redirects; response bounds; generated image decoding; exact data copy;
and native file-writer replacement/reopen with generated PNG/GIF files. Tests use controlled
continuations, memory-only secure storage, local URLProtocol responses, generated ImageIO media,
and private temporary destinations. They do not use Slack credentials, network, Keychain, real
clipboard, permission prompts, or UI automation.

`SlackEmojiDebugFixture.services(exporter:)` supplies two generated workspaces, static/animated
images, aliases, and one missing alias with an explicit fixture label. Its default exporter uses
the real native copy/Save UI when an authorized native review invokes it. Generated fixture
tokens `xoxb-generated-one` and `xoxb-generated-two` address those workspaces; another generated
bot-form token produces a third workspace. Production never silently substitutes generated data.

Root registry integration and all six original Slack suites passed targeted Xcode tests in
`/tmp/commandly-video-targeted-sept17-slack.log`. The clean signed build passed in
`/tmp/commandly-video-native-sept17-slack-clean.log`, followed by deep strict and exact bundle/team
signature checks. Generated native acceptance passed discovery, explicit refresh, local alias search,
static/animated previews, missing-alias guidance, arrow/Return shortcode copy, Command–Shift–C image
copy, Save/cancel, workspace switching, generated connection setup and Escape/search restoration.
The exported GIF reopened with all four 64 × 64 frames (719 bytes, mode 0600). Compact spacing,
larger text and light appearance fit, including the scrollable connection sheet. The user's original
Comfortable/Default/System preferences were restored afterward.

The service-level cross-model settlement correction postdates that native build. Its thirty isolated
tests and root `make verify` passed (`/tmp/commandly-video-verify-sept17-slack.log`), including the
new registry integration test and unchanged File Search copy assertion. A fresh signed build remains
pending. VoiceOver,
Reduce Motion in the real app, and user-owned token/provider acceptance remain outstanding. Live acceptance
must separately check authorized installation, current exact scope evidence, live inventory and
media-host compatibility, expiry/revocation, and real Keychain persistence/removal. The generated
tests establish none of these external states.
