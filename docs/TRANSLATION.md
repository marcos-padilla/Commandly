# Native Translation

Translate (`text.translate`) is an original, registered launcher application using Apple's public Translation framework. Translate a Word (`text.translate.word`) opens a focused single-line version of the same native engine. It is not a dictionary, a mock production translation, or an AI-provider prompt. The app target requires macOS 27; the selected Translation strategy APIs are available since macOS 26.4.

## Behavior

Opening either entry creates a fresh session model and reads supported-language metadata only. It does not create a `TranslationSession`, translate text, ask for downloads, read selected text, or read the clipboard. The default target matches this Mac's preferred native locale variant first, then its language/script, then its base language. An explicit region or script is not silently replaced by the first base-language match. A base-language preference without a region does not determine the person's regional preference; the visible target remains editable. Refresh preserves a still-supported explicit target choice. Source defaults to Detect Language and can be chosen explicitly.

The pickers contain the actual full `LanguageAvailability(preferredStrategy: .highFidelity).supportedLanguages` catalog returned on this Mac. The adapter preserves native language identifiers, including script and regional distinctions, removes exact duplicate identifiers, and sorts localized display names. No fixed shortlist silently limits source or target. A supported language does not imply that every pairing works or that its model is installed. Selected pairs are checked with `status(from:to:)`; unsupported pairs are clearly shown and do not enable Translate.

The app uses `.highFidelity` for both catalog and session. Apple documents that this prefers Apple Intelligence translation where supported, with its native traditional-model fallback where it is not. Commandly does not silently substitute a remote AI response.

Type or paste text, review source and target, and choose Translate. Command–Return submits paragraphs; Return submits the word entry. A nil native source allows Apple's automatic source detection and its own ambiguity prompt. The app intentionally does not reject short words using an unreliable preflight detector; choosing the source explicitly is available when detection fails. Paragraph input retains newlines and whitespace, with a submission limit of 10,000 characters and 64 KiB UTF-8. Results are bounded to 256 KiB UTF-8.

Translation may display Apple's native language-download consent. With a chosen source and target, Download Languages… separately calls `prepareTranslation()`; it never submits the draft. Apple may return from preparation while a previously approved download is still in progress, so the app does not claim preparation guarantees installation. Refresh Languages rechecks metadata. Language selection, editing, clearing, or leaving cancels the local request and clears an older reviewed result. Cancel preserves the draft for retry. Leaving clears input and result.

Results display the actual native source/target languages and selectable text. Copy Translation (Command–Shift–C) is explicit; no copy occurs on success. A copy error keeps the reviewed result for retry. Swap exchanges chosen source/target without submitting text.

## Ownership and concurrency

- `Packages/Sources/Infrastructure/TextTranslation.swift`: bounded sendable values, typed errors, read-only catalog, explicit translation/preparation, and explicit copy protocols.
- `Commandly/Services/Translation`: native language metadata, a view-bound request bridge, native SwiftUI session host, live and injectable service composition, and the explicit clipboard adapter.
- `Commandly/Scenes/Launcher/Commands/Translation`: observable model and original SwiftUI surface.
- `Commandly/Scenes/Launcher/Applications/TranslationApplication.swift`: application plus focused word tool through the shared session, search, application hotkey, and Command Wheel routes.

Each live launcher session receives a new bridge. The bridge owns immutable request values and one checked continuation, never a `TranslationSession`. A request UUID keys a native SwiftUI child with one stable `@State` configuration. Only one callback may claim a request. That `.translationTask` action uses its native session for exactly one awaited `translate` or `prepareTranslation` call. It does not retain the session, invoke it concurrently, pass it to another task, or call any session API after the await. Removing the host lets Apple's SwiftUI lifecycle cancel its session.

This restriction follows Apple's session-lifetime contract: a session must not be reused after the hosting view disappears or its configuration changes. Cancellation is handled by operation identity and continuation retirement, rather than retaining a session cancellation handle that may become invalid. Late completion and late cancellation from an old operation cannot affect a newer request. Model generations separately reject late results, stale language metadata, and stale pairing checks, even from an injected adapter that ignores cancellation.

`NativeTranslationTaskView.swift` alone uses `@preconcurrency import Translation`. SDK 27 exposes a non-Sendable `TranslationSession` with asynchronous concurrent methods, which otherwise triggers a diagnostic at the documented SwiftUI callback pattern under default MainActor isolation. This compatibility import addresses that SDK annotation gap narrowly. There is no unchecked Sendable wrapper or shared native session; strict concurrency is enabled for the rest of the code. Native metadata calls create their own availability instance and run off the main actor.

## Privacy and recovery

Apple states that `TranslationSession` processes original and translated content on-device. Apple may collect framework usage/performance metrics, including the app identifier and requested languages, but not the original or translated text. Commandly adds no network client, AI-provider handoff, analytics, logging, file persistence, automatic clipboard reads, or permission request to this feature.

Language files are operating-system resources shared across apps. Apple's native download flow obtains consent. Once approved, an OS-managed download may continue after cancellation, dismissal, or leaving Commandly. The app's cancellation message does not promise to stop that download. No language files are deleted by Commandly. Manage them in System Settings → General → Language & Region → Translation Languages.

Unknown-source errors ask for an explicit source. Missing models offer a retry through Apple's native prompt or explicit preparation. Unsupported languages/pairs ask for a different selection. Empty or oversized input is rejected before invoking the translator. Errors are typed and sanitized; native error descriptions that might contain private content are not shown. A normal explicit copy participates in Clipboard History only under its existing enabled behavior. No new entitlement or privacy usage string is required by this app integration.

## Accessibility

The view uses the shared native launcher chrome, a header trait, labeled source/target pickers, labeled editable input, explicit action names, progress indicators, selectable review text, keyboard submission, copy shortcut, and the shared Escape cancellation path. Initial input focus is requested on the next main run-loop turn after attachment. Accessibility children are contained so the screen label does not replace every control's label. Layout is scrollable within the launcher and uses density-aware spacing and semantic controls.

## Validation and limits

The 25 added tests use injected catalogs/translators/copiers and generated text only. They cover full native catalog retention, canonical regional/script preference selection (Hant/Hans and pt-PT/pt-BR), and preserving an explicit choice during refresh; explicit auto/chosen-source and word submission; unsupported and unknown pair rejection; independent grapheme/UTF-8 input limits; output limits; explicit preparation without translation; copy success/failure and retained review; source ambiguity recovery; draft edits, cancellation, leaving, and late-result replacement races; stale language-pair metadata; native error sanitization and language identifier mapping; once-only callback claims, retired continuation completion/cancellation, and mismatched outcome rejection; shared search/hotkey/Command Wheel routing; distinct live session bridge identities without native work; and visibly labeled generated UI fixture output with unsupported fixture rejection and recording-only copy.

Production and all test sources have been compiled against the installed SDK with the app's Swift 6 strict-concurrency and MainActor defaults. The initial 21 tests passed in the root app suite and full `make verify` (`/tmp/commandly-video-verify-tranche8-translation.log`). After the locale-selection fix and generated fixture additions, an isolated SwiftPM harness executed the actual bridge, model, native mapping, service, and shared launcher-session sources: all 23 non-registration tests passed (`/tmp/commandly-translation-slice/isolated-tests-final.log`). The final 25-test app suite and root verification await the next combined run. Compilation and injected tests are not evidence that native download/translation UI was exercised.

Native download consent, actual translation output/quality, unsupported-device behavior, and VoiceOver/keyboard rendering require an unlocked Mac and an explicit native acceptance run. Those checks are pending. Automated tests neither download models nor access real clipboard contents or translations. This slice implements the video's text translation/auto-source/chosen-languages/word-entry scope; it does not claim dictionary definitions, pronunciation playback, or every feature in the video.

## Generated UI acceptance fixture

A DEBUG-only, opt-in `TranslationDebugFixture.services` supports exactly `hello`, source Detect Language or English, and target Spanish. It returns `hola` followed by the visible notice “Generated UI fixture — no native translation ran.” Unsupported input and pairs are rejected. Its copy adapter records only in an actor, without accessing the system pasteboard. It has no native bridge, model downloads, translation session, or network client. This fixture is for UI interaction/geometry tests; it supplies no evidence of actual native translation accuracy or consent behavior. Live services always use the native framework and a fresh session bridge.

## Primary API evidence

Checked using the installed Xcode 27 Translation and _Translation_SwiftUI swiftinterfaces and current Apple documentation:

- [TranslationSession and on-device privacy](https://developer.apple.com/documentation/translation/translationsession)
- [SwiftUI translationTask lifecycle](https://developer.apple.com/documentation/swiftui/view/translationtask(_:action:))
- [Session configuration with preferred strategy](https://developer.apple.com/documentation/translation/translationsession/configuration/init(source:target:preferredstrategy:))
- [Actual supported-language catalog](https://developer.apple.com/documentation/translation/languageavailability/supportedlanguages)
- [High-fidelity strategy and native fallback](https://developer.apple.com/documentation/translation/translationsession/strategy/highfidelity)
- [Explicit language preparation](https://developer.apple.com/documentation/translation/translationsession/preparetranslation())
- [Native cancellation and continued downloads](https://developer.apple.com/documentation/translation/translationsession/cancel())
- [Ambiguous source language](https://developer.apple.com/documentation/translation/translationerror/unabletoidentifylanguage)
