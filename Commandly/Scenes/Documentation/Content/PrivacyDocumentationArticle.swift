enum PrivacyDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.privacy-permissions",
        title: "Privacy, Permissions & Local Data",
        subtitle: "Understand what stays on your Mac and when Commandly asks for access.",
        systemImage: "lock.shield",
        category: .settingsAndPrivacy,
        order: 310,
        documentation: LauncherApplicationDocumentation(
            category: .settingsAndPrivacy,
            overview: "Commandly is sandboxed and requests access in context, after an action that benefits from it. Most implemented features use local macOS frameworks and local storage; the calculator’s live currency conversion is the explicit network-backed exception.",
            sections: [
                DocumentationSection(
                    id: "privacy-request-policy",
                    title: "Permission policy",
                    blocks: [
                        .bullets("privacy-request-policy-list", [
                            "A permission is tied to a user benefit and requested only after you activate the relevant control or action.",
                            "Permission denial does not block onboarding completion or unrelated features.",
                            "For Calendar, Contacts, selected folders, and Accessibility, Settings provides a recovery path when access is denied or restricted. Feature-specific access such as Finder Automation is recovered in System Settings.",
                            "Commandly documents each entitlement and requests interactive permissions only in context. Temporary uninstall exceptions grant broader read-write filesystem scope than selected folders; that scope is disclosed below and limited by Commandly's review-first workflow.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-active-permissions",
                    title: "Current permissions and access",
                    blocks: [
                        .bullets("privacy-active-permissions-list", [
                            "Files and Folders: lets File Search index and manage folders you explicitly select. Commandly stores versioned security-scoped bookmarks so it can restore that scope later.",
                            "Downloads read access: lets Recent Downloads list, open, reveal, and copy the URL of top-level downloads. It does not grant that application permission to modify Downloads.",
                            "Accessibility: required when you apply a Window Layout. Commandly prompts in that workflow and provides recovery steps if access is denied.",
                            "Automation for Finder: macOS may request it when File Search or an installed application's actions ask Finder to show an Info window. Recover it in System Settings → Privacy & Security → Automation → Commandly → Finder.",
                            "Application uninstall scope: sandbox temporary file-access exceptions let Commandly discover a selected app's related files under the real user Library, /Applications, and /Library. Nothing is removed automatically; Commandly presents a review list and trashes only the items you explicitly confirm.",
                            "Open at Login: uses the native login-item service. It is not a TCC privacy permission, but macOS may require approval in Login Items settings.",
                            "Calendar and Contacts: optional onboarding permissions reserved for future schedule and people applications. Current Commandly screens do not surface calendar events or contacts.",
                            "Clipboard History: pasteboard monitoring and on-device text recognition do not show a TCC prompt. Monitoring runs in the background while Commandly is running, and captured content must never be logged.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-uninstall-scope",
                    title: "Application uninstall access",
                    blocks: [
                        .paragraph(
                            "privacy-uninstall-scope-summary",
                            "Uninstall discovery uses temporary home-relative and absolute-path read-write sandbox exceptions for locations where macOS applications and their support files commonly live, including ~/Library, /Applications, and /Library. This is broader filesystem scope than a folder selected through File Search, so Commandly keeps the workflow explicit and review-first."
                        ),
                        .bullets("privacy-uninstall-scope-guardrails", [
                            "You start uninstall from the selected installed application's actions panel.",
                            "Commandly matches the app's bundle identifier and known helper prefixes, then shows the discovered bundle and related files before acting.",
                            "Only reviewed items that you confirm are sent to Trash through native macOS APIs.",
                            "Protected or unavailable paths can fail. Commandly reports partial failures instead of claiming a complete wipe."
                        ]),
                        .callout(
                            "privacy-uninstall-scope-control",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "No background cleanup",
                                text: "The entitlement grants filesystem access. Commandly limits its use of that scope to a user-selected app, a review screen, and explicit confirmation; it does not perform background cleanup."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-local-storage",
                    title: "What is stored locally",
                    blocks: [
                        .bullets("privacy-local-storage-list", [
                            "General settings, installed-app preferences, registered-app aliases, global hotkeys, enablement, and non-secret configuration are stored in UserDefaults.",
                            "File Search stores its index in Commandly’s Application Support container and stores security-scoped folder bookmarks locally.",
                            "Productivity Library stores user-authored snippets, quick notes, Quicklinks, and emoji keywords in Commandly’s Application Support container.",
                            "Installed-app usage ranking stores only a local open count and last-opened timestamp per bundle identifier.",
                            "Custom window-layout geometry is stored as a non-secret local preference.",
                        ]),
                        .callout(
                            "privacy-local-storage-secrets",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "No secrets in preferences",
                                text: "UserDefaults-backed app configuration is for non-secret values only. Commandly does not currently expose a credential field in the registered-application schema."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-session-data",
                    title: "Session-only data",
                    blocks: [
                        .bullets("privacy-session-data-list", [
                            "Clipboard History entries are held in memory for the current process; they are not persisted to disk in this phase.",
                            "Calculator history, previous answers, variables, and named values are in-process session state.",
                            "Timers & Focus sessions are in-process and are not restored after Commandly quits.",
                            "Launcher search history is not persisted.",
                            "Calculator live predictions and partial input are not persisted.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-content-handling",
                    title: "Sensitive content handling",
                    blocks: [
                        .bullets("privacy-content-handling-list", [
                            "Commandly must not log clipboard contents, OCR text, extracted file text, calculator expressions, calculator results, private URLs, file contents, credentials, or full search history.",
                            "Clipboard OCR and readable-file extraction use on-device Vision and PDFKit processing at capture time.",
                            "A clipboard or file copy occurs only after an explicit action, except for pasteboard monitoring that records newly copied items in the in-memory history.",
                            "Copy and Open Notes places a calculation line on the pasteboard and opens Notes; it does not automate or modify a note.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-network",
                    title: "Network use",
                    blocks: [
                        .paragraph(
                            "privacy-network-summary",
                            "Core search, file search, clipboard analysis, snippets, timers, window layouts, system activity, emoji search, text case, color tools, Dictionary, fonts, and typing practice are local. Calculator currency conversion requests public exchange-rate data from Frankfurter at api.frankfurter.app and requires no API key."
                        ),
                        .callout(
                            "privacy-network-currency",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Rates are never invented",
                                text: "If currency data is unavailable, Commandly surfaces an error instead of fabricating a conversion. Other calculator categories remain available offline."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "privacy-recovery",
                    title: "Review or recover access",
                    blocks: [
                        .steps("privacy-recovery-steps", [
                            "Open Settings with Command–Comma and choose Permissions.",
                            "Review the state next to Calendar, Contacts, Files and Folders, or Accessibility.",
                            "Choose the available action. If one of those supported permissions was denied, Commandly opens its relevant System Settings privacy pane.",
                            "For folder scope, use Manage Folders again and choose the folders Commandly should access.",
                            "For Finder Automation, open System Settings → Privacy & Security → Automation and allow Commandly to control Finder. This permission is not listed in Commandly's Permissions pane.",
                        ]),
                    ]
                ),
            ],
            keywords: [
                "privacy", "permissions", "sandbox", "local data", "UserDefaults", "Application Support",
                "Accessibility", "Files and Folders", "Calendar", "Contacts", "Automation", "Finder",
                "clipboard", "OCR", "network", "Frankfurter", "currency", "offline",
            ]
        )
    )
}
