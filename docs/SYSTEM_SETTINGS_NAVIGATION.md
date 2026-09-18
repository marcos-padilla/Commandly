# System Settings navigation

The registered System Settings application provides a searchable local catalog of macOS pages. Its 27 settings intents and the separate Open macOS System Settings tool are independently discoverable registry tools. They can use existing launcher search, shortcuts, or Command Wheel enablement. The catalog opens no application and reads no settings metadata until the user invokes Open. Return opens the selected page; Command-K exposes selected-page and application-only actions.

## Display intent mapping

Display Settings, Display Brightness Settings, Display Color Profile Settings, Display Orientation Settings, Display Resolution Settings, and Display Scaling Settings **all open Displays**. Each tool subtitle and the focused catalog show that shared destination. These are navigation commands; they do not manipulate brightness, profiles, rotation, scale or display modes. The existing Display Resolution preview application remains separate.

Apple documents resolution, brightness, color profile and rotation under Displays and notes that options depend on connected hardware. Scaling uses the available resolution/text-size choices. There is no promise to select a particular display, reveal a control, or apply a setting. [Apple Displays guide](https://support.apple.com/guide/mac-help/displays-settings-on-mac-mh40768/mac)

## Native boundary and evidence

`Infrastructure/SystemSettingsNavigation.swift` defines fixed destination identifiers, a navigation protocol and typed results/errors. `SystemSettingsCatalog` owns static discovery metadata. `SystemSettingsViewModel` owns selected-item actions, cancellation and feedback. `NativeSystemSettingsResolver` reads bounded metadata on its actor; `NativeSystemSettingsOpener` hands URLs to NSWorkspace through an injected MainActor port.

The installed Apple System Settings app at `/System/Applications/System Settings.app` declares bundle ID `com.apple.systempreferences` and the non-private `x-apple.systempreferences` URL scheme in its Info.plist. The separately declared `settings-navigation` scheme is explicitly private and is never used. Each fixed pane ID is verified from the matching Apple extension in `/System/Library/ExtensionKit/Extensions`. Apple's current Displays help HTML also exposes `x-help-action://openPrefPane?bundleId=com.apple.Displays-Settings.extension`, matching the installed DisplaysExt metadata.

Navigation uses the advertised `x-apple.systempreferences:<verified bundle ID>` form through public [NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)). The app is specified explicitly, so a third-party default scheme handler is not used. Both native open configurations disable [running-application substitution](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/allowsrunningapplicationsubstitution), preserving the verified system-volume recipient even if another installation is running. They do not force a new instance. URLComponents constructs URLs only from a bounded Apple identifier grammar. There are no user-supplied URLs, query parameters or subpane anchors. Apple's published help IDs and installed metadata establish the fixed destinations; this is not a documented guarantee that every macOS build will display a requested page.

Before every request, the actor confirms the fixed application identity, public scheme registration and requested extension identity. Metadata is limited to 128 KiB per plist; malformed, missing, oversized or symlinked bundles/plists fail or fall back. Production roots are fixed on the system volume and cannot be changed through user preferences or tool arguments. File reads use Foundation only; bundle code is not loaded. Injected alternative roots exist solely for generated-file tests.

The SDK's NSWorkspace header describes success as successful launch/open completion. Therefore the service reports `requestedPane`, not proof of the displayed UI. Commandly does not inspect System Settings windows or use private frameworks, UI automation, AppleScript, shell commands, permission prompts, extra entitlements or sandbox exceptions.

## Fallback, cancellation and enabled commands

If the destination metadata is unavailable, the public scheme is no longer advertised, or URL dispatch fails, the service attempts application-only opening once. The user is told that direct navigation failed and to select the intended page in the sidebar or search. If app opening also fails, a typed recoverable error offers retry or opening System Settings from the Apple menu. No failed operation is described as successfully opening a pane.

In the catalog, app-only fallback keeps recovery guidance visible. In a background tool, it returns that guidance through the existing command failure notice, since the requested pane was not reached. A successful direct request dismisses the launcher. Opening the application-only tool is explicit and has no promised page.

Navigation refuses disabled contexts, unknown tool IDs and unexpected arguments. Registry inherited enablement excludes disabled applications and their tools. The focused model also disables dispatch when its context is disabled, search has no selection or an operation is active. Search/selection changes and stopping the model cancel queued work and suppress stale completions. Cancellation is checked after metadata resolution and before both URL and fallback dispatch. A navigation already handed to macOS cannot be withdrawn; cancellation does not claim to close System Settings.

## Privacy, language and accessibility

Search is bounded to 256 UTF-8 bytes and filters static names/keywords. It reads no settings values, user files, device state, network or account data and persists no query/history. Opening reads only the fixed Apple metadata described above. NSWorkspace navigation itself does not mutate settings; macOS owns any page behavior after handoff, and the user chooses changes there.

The current Commandly catalog has English labels, matching the app's current UI. Fixed bundle IDs are independent of display language; macOS may localize titles and change available pages by release or hardware. Fallback does not invent a destination if the known metadata is absent.

The original UI uses shared Commandly search/list/detail composition, explicit destination subtitles, descriptive system icons, text headers and labeled buttons. Arrow keys select, Return opens, Command-K shows actions, and Escape cancels a pending request, clears search or goes back. Search focus is requested after attachment. Detail text explains shared destinations and hardware limits; meaning does not rely on icons alone. The detail scrolls at compact heights or enlarged text sizes, keeping the Open action and guidance reachable.

## Verification

Deterministic tests use generated temporary app/extension plists and injected workspace/opening ports. They cover all catalog IDs, URL construction/malformed inputs, space encoding, metadata identity and size, missing/private schemes, symlinks, pinned native launch configuration, explicit navigation, one-time fallback, failures, disabled dispatch, queued/in-flight cancellation, stale results and retry. Tests never open System Settings, prompt for permission, modify settings or access a real clipboard.

The tranche-17 aggregate passed in `/tmp/commandly-video-verify-tranche17-final.log`. On September 17,
the clean signed sandboxed app opened Displays from the catalog and Sound and Date & Time through
their direct tools. The actual System Settings windows showed the requested pages. No preference
was changed. Build receipt: `/tmp/commandly-video-native-sept17-slack-clean.log`; deep strict and
exact app/team signature checks passed. These three native checks do not establish every destination
on every macOS release; unavailable-pane fallback and other destinations retain their separate gates.
