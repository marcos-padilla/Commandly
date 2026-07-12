# Permissions

Commandly currently uses the App Sandbox with user-selected read-only file access only. It does **not** request Accessibility, Apple Events, Screen Recording, Contacts, Calendar, Camera, Microphone, or Location.

## Possible future permissions

| Permission | Potential feature | Why it may be needed | Prompt timing |
|------------|-------------------|----------------------|---------------|
| Accessibility | Window management, UI automation helpers | Observe/control windows | When user enables window tools |
| Apple Events | Controlling other apps | Automate supported apps | Per automation feature |
| Screen Recording | Capture-driven workflows | Read screen content | When user starts capture feature |
| Full Disk / broader files | Deep file search | Search outside sandbox picks | When user enables file index |
| Notifications | Command completion alerts | Notify asynchronously | When user enables notifications |
| Pasteboard (no TCC prompt, but sensitive) | Clipboard history | Read clipboard changes | When user enables clipboard history |

## Policy for all future permissions

1. Document user benefit before enabling.
2. Request only when the user activates the feature.
3. Explain before the system prompt when possible.
4. Handle denial gracefully.
5. Provide Settings recovery instructions.
6. Keep scope minimal.
7. Cover behavior with mocked tests — never require real grants in CI.
