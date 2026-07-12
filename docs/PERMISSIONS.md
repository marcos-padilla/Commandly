# Permissions

Commandly uses the App Sandbox. Permissions are requested only after explicit user intent (for example, an onboarding **Grant Access** button). Continue remains available if the user skips.

## Active permissions

| Permission | Feature benefit | Prompt timing | Recovery |
|------------|-----------------|---------------|----------|
| Calendar | Surface upcoming meetings from the launcher | Onboarding Grant Access or later feature enablement | System Settings → Privacy & Security → Calendars |
| Contacts | Find people quickly from the launcher | Onboarding Grant Access or later feature enablement | System Settings → Privacy & Security → Contacts |
| Files and Folders | Search folders the user selects | Onboarding Grant Access shows a folder picker; security-scoped bookmarks are stored | Re-run picker or System Settings → Files and Folders |
| Accessibility | Window layouts and deeper keyboard automation | Onboarding Grant Access (system trust prompt) | System Settings → Privacy & Security → Accessibility |
| Open at Login | Launch Commandly at sign-in | Setup toggle during onboarding | System Settings → General → Login Items |

## Entitlements and usage strings

- Sandbox remains enabled.
- `com.apple.security.files.user-selected.read-only` for folder picks.
- `com.apple.security.personal-information.calendars`
- `com.apple.security.personal-information.addressbook`
- Info.plist includes `NSCalendarsFullAccessUsageDescription`, `NSCalendarsUsageDescription`, and `NSContactsUsageDescription`.

## Not requested yet

Apple Events, Screen Recording, Notifications, Camera, Microphone, and Location remain unimplemented. Clipboard history is opt-in and does not use a TCC prompt, but content must never be logged.

## Login items

Open at Login uses `SMAppService.mainApp` and is only registered after the user enables it in onboarding (or a future Settings control). It is not a TCC permission, but macOS may still require approval under **System Settings → General → Login Items**. Denial or pending approval must leave the app usable; the preference is persisted and the UI explains how to recover.

## Policy for all permissions

1. Document user benefit before enabling.
2. Request only when the user activates the control.
3. Explain why before the system prompt when possible.
4. Handle denial gracefully; never block onboarding completion.
5. Provide Settings recovery instructions.
6. Keep scope minimal.
7. Cover behavior with mocked tests — never require real grants in CI.
