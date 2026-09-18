# Dictation

Commandly Dictation is an explicit-start, on-device microphone transcription application. It provides supported-language and input choices, live provisional text, Stop & Review, editable text, explicit Copy, optional saved text history, and optional AI writing-style previews. The original UI uses native controls and Commandly typography; no competitor source, assets, icons, or exact layout is used.

Video ledger scope is rows **13–16**: current-app dictation (0:52), multilingual dictation (0:57), writing styles (1:01), and dictation history (1:07). Rows 17–19 concern window layouts and key remapping. Cross-app insertion remains an open companion feature: this slice provides explicit copy/paste and does not treat the companion's currently unsupported selection schema as implemented authority.

## Native implementation

Infrastructure owns framework-free capture, language, microphone permission, and transcript contracts in `Dictation.swift`. `NativeDictationService` owns one serial Dispatch actor executor shared across capture and language downloads. Device discovery creates no input. The service creates an `AVCaptureSession` and `AVCaptureDeviceInput` only after the user's Start action receives microphone authorization and confirms installed language assets.

macOS 27 `CaptureInputSequenceProvider` converts capture samples into the format reported by `SpeechAnalyzer.bestAvailableAudioFormat`. The capture session must explicitly add both its input and the provider's `captureAudioDataOutput`. `SpeechTranscriber` is preferred where its hardware and locale support permit it; `DictationTranscriber` supplies additional native on-device locales. There is no `SFSpeechRecognizer` or server-recognition fallback. A supported equivalent of the system locale is preselected. The public transcriber initializers take a chosen locale; this application does not claim automatic detection of the spoken language.

Official APIs and the installed macOS 27 SDK were inspected on 2026-09-14:

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [live audio recognition](https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio), and [CaptureInputSequenceProvider](https://developer.apple.com/documentation/speech/captureinputsequenceprovider) establish the capture and analysis lifecycle.
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) and [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber) expose supported/installed locale information, results, and on-device transcription.
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory) owns system-managed model downloads and locale reservations.
- [Speech-recognition permission](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition) explicitly distinguishes server-based `SFSpeechRecognizer` authorization from on-device `SpeechAnalyzer` modules.

Opening Dictation lists support and checks the selected model; it never prompts or downloads. Download Language is a separate explicit action. Apple controls model sizes, shared storage, updates, and retention. Commandly does not promise a model byte budget or remove Apple's shared files. When necessary, an explicit new-language download releases an unused reservation belonging to Commandly; it does not release other applications' reservations. Download and capture cannot overlap through the shared service. Cancellation requests cancellation of the installation progress; shared assets may remain.

## Lifecycle and limits

Each recording has a UUID allocated before asynchronous permission/model preparation. Cancellation invalidates that identity and stops a matching native session; late grants or completions cannot reopen the microphone. The native owner revalidates identity and cancellation after suspension points. Start and stop run on its serial executor, never on MainActor. Audio is never written to a file or retained as a complete recording.

Stop first stops the microphone, then cancels only input analysis. The API returns the last analyzed timestamp when the input task is cancelled; an uncancelled finalizer uses that timestamp to finish recognition and drains result updates before delivering review text. Cancel instead cancels analysis and results, stops capture, waits for tracked finalization, and restores the earlier draft. A second Start cannot overlap shutdown. Runtime interruption, device disconnection, and unexpected end of the native audio sequence stop input and preserve the latest available transcript with a recoverable error. Route removal/session stop cancels input and clears the session's text. The native owner drops transcript references after shutdown.

A recording is limited to five minutes by a cancellable Dispatch timer. Full transcript snapshots are limited to 64 KiB UTF-8. The timestamped result buffer replaces revised word ranges without duplicating finalized words. Only bounded complete snapshots reach MainActor (`bufferingNewest(1)`); terminal failure/success includes the latest complete snapshot so an overwritten intermediate update does not lose available text. Provisional text is visibly identified if recognition fails before finalization.

## Review, optional AI, and history

Text is editable only after capture stops. Copy and Save are explicit actions. Cancelling a replacement recording restores the earlier text, identity, language, save status, and duration; saving later edits updates the same history record. The source language is pinned to its recorded/saved draft even when another language is chosen for the next capture.

Writing Style uses the existing configured `QuickAIServicing` transport and connection metadata. The selected provider/model is shown before Preview Style. Only the reviewed text (up to 8 KiB) and the chosen original style instruction are sent. Audio, clipboard contents, history, and current-app contents are not read or attached. Stream output and the final response are limited to 32 KiB; truncated, empty, tool-containing, or nontext replies are rejected. Preview results do not replace the original until Use This Version. Source/style/provider edits and cancellation reject late responses. The user can edit the proposal or keep the original. No AI request occurs during load, style selection, or recording.

Save to History writes only text, recognition language, date, and duration to `Application Support/Commandly/Dictation/history.json` in the app container. No automatic history is collected, and no raw audio is saved. A single injected actor serializes read-modify-write. Reads reject symlink files/final directories, malformed documents, unsupported versions, duplicates, oversized files, or invalid entries. Writes create a private `0700` directory and `0600` file, flush a temporary file, then rename atomically. History permits 50 records and 2 MiB with no silent eviction. Re-saving the current draft updates its record. Search, copy, individual confirmed deletion, and confirmed Clear History are available. Clear can reset a corrupt history document and never changes the current draft. File permissions restrict other accounts; history is not separately encrypted. System backups or copies outside Commandly are outside Clear History's scope.

No microphone IDs, audio, recognized text, provider output, or private paths are logged. Explicit clipboard copies follow the user's normal Clipboard History settings. This application does not monitor a focused external field or insert automatically.

## Permission and metadata integration

Only explicit Start calls microphone `requestAccess(for: .audio)` when authorization is undetermined. Denied/restricted states do not prompt repeatedly. The UI explains the benefit before Start and provides Microphone Settings plus retry/input refresh. Tests inject permission responses and do not access real TCC.

Required app-target metadata:

- `NSMicrophoneUsageDescription`: `Commandly uses the microphone only when you start Dictation, to transcribe speech on this Mac.`
- `com.apple.security.device.microphone = true` for the sandbox's microphone access, following the current [microphone entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.microphone).
- `com.apple.security.device.audio-input = true` for Hardened Runtime audio input, following the current [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input).
- Link the system Speech and AVFoundation frameworks. No third-party dependency is introduced.

Do not add or request server speech recognition authorization: there is no `SFSpeechRecognizer` path in this implementation, so `NSSpeechRecognitionUsageDescription` and a server speech prompt are not part of this slice. A central Settings microphone permission tile may reuse the feature's preflight/request behavior, but opening Settings must remain read-only.

## Keyboard and accessibility

Command–Return explicitly starts or stops recording; Return remains available for multiline editing. Command–Shift–C copies reviewed text. Native pickers, buttons, text editors, history List, and search participate in keyboard focus. Escape cancels the nearest history confirmation/panel, download, active recording, or AI preview before offering to discard unsaved review text. Back uses the same ordering. Text editors receive focus after a capture finishes or a style is applied. Native history selection supports arrow navigation and Return copy; the search field receives initial focus. Status, error, provisional-result, recording indicator, and duration text accompany symbols. Detail accessibility identities refresh per saved item. All text uses Commandly's scalable typography; no flashing/pulsing animation is required.

## Verification boundary

`DictationViewModelTests`, `DictationWritingStyleTests`, `DictationHistoryStoreTests`, `NativeDictationTranscriptTests`, `NativeDictationPermissionTests`, and `DictationApplicationTests` use controlled actors, generated text/PCM, timestamped attributed text, and private temporary file fixtures. They do not use the real microphone, permission prompts, speech models, provider network, clipboard, or saved user history. Generated PCM is converted to a valid signed 16-bit interleaved speech input format; production always asks the selected native module for its compatible format.

`DictationDebugFixture.services(pasteboard:quickAI:)` is DEBUG-only, explicitly labeled Generated UI Fixture, and supports Start → provisional preview → Stop → review without microphone or speech recognition. Its history is memory-only. It is for interaction acceptance, not evidence of real transcription accuracy.

Real capture accuracy, actual microphone authorization, device interruption, OS model installation/cancellation, and a real provider style response require separate explicit manual acceptance. A passing fake/PCM suite must not be reported as that live permission or speech test.

Aggregate app verification passed on September 14, 2026 in `/tmp/commandly-video-verify-tranche14-dictation-channel.log`, including 25 dictation cases. Read-only native speech inspection reported 45 supported SpeechTranscriber locales and nine English entries in `installedLocales`; however, AssetInventory for a constructed equivalent English module reported `supported`, requiring installation before recognition. The generated-audio probe stopped at this preflight without downloading assets or accessing a microphone. These results do not establish successful transcription.

Native generated-fixture acceptance subsequently passed Start/Stop with Command-Return, provisional
and final review, multiline Return, Command-Shift-C, explicit save and searchable history copy,
optional generated style preview/Keep Original, and replacement-recording Cancel restoring the
saved draft and identity. The fixture used no microphone, actual recognition, network, or persistent
user history. New recording clears old completion status, collapses the optional style section,
and scrolls the transcript back into view. These corrections passed aggregate verification and a
clean signed build in tranche 16. Native follow-up confirmed that starting from expanded styles at
the bottom of the scroll view collapses that section, returns scroll to the top, shows the recording
indicator and transcript, and clears the previous saved status. Cancel restored the saved draft.
