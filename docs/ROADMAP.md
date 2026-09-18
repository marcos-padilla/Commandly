# Roadmap

Status legend: ✅ done · 🚧 in progress · 🔜 next · ⏳ later

1. ✅ **Project foundation** — structure, modules, docs, scripts, placeholder UI
2. ✅ **First-run onboarding** — multi-step welcome, feature tour, setup, permissions, and hotkey reveal
3. ✅ **Menu bar agent shell** — status item with Settings, Open Commandly, and Quit
4. ✅ **Settings window** — quiet sidebar + General / Permissions / About
5. ✅ **Launcher window (frontend)** — floating palette UI, ⌥Space toggle, registered applications
6. ✅ **Command registration + Clipboard History** — scalable command manifests/actions; first real view command
7. ✅ **Keyboard navigation polish** — actions menu consistency, deeper list UX; searchable application actions panel (right-click / ⌘K)
8. ✅ **Application launching** — enumerate installed apps + open via Infrastructure adapters
9. ✅ **Quick links, snippets, and notes** — local persistent Productivity Library with sharing and clipboard templates
10. ✅ **Search providers (commands + apps)** — SearchKit-backed ranked, cancellable search + autocomplete, including File Search
11. ✅ **Calculator in search** — CalculatorKit engine pinned above results (arithmetic, scientific, %, units, currency, dates, time zones)
12. ⏳ **Clipboard history persistence** — optional durable store, privacy-reviewed
13. ✅ **Window management** — 58 presets and custom layouts with contextual Accessibility prompting
14. ⏳ **BusinessMate360 integration** — product-specific commands
15. ⏳ **Extension prototype** — after ADR, likely declarative or signed native first
16. ⏳ **Distribution and updates** — signing, notarization, updater decision
17. ✅ **File search provider** — cancellable, persistent, content-aware files provider behind SearchKit
18. 🚧 **BYOK AI + Finder AI vertical slice** — accepted privacy/tool-safety design, AIKit and
    secure provider setup implemented; the initial non-streaming text/tool runtime covers OpenAI,
    Anthropic, Gemini, Mistral, Groq, xAI, OpenRouter, and loopback Ollama while broader AI product
    work remains in progress
19. ✅ **Native productivity applications** — recent downloads, timers/focus, calculation history, system activity, emoji, text case, color, dictionary, fonts, and typing practice
20. ✅ **Shelf staging board** — one active-display temporary board with file/folder drag-in,
    multi-item drag-out, clipboard URL/text/image import, native sharing and file actions, global and
    menu-bar entry points, whole-surface movement, details, and settings
21. ✅ **Command Wheel** — configurable radial profiles over the shared command engine, with
    hold/release and toggle input, keyboard navigation, submenus, context rules, dynamic
    recent/frequent commands, multi-display placement, accessible Settings, and versioned transfer
22. ✅ **Recurring finance foundation** — local subscription ledger, normalized dashboard metrics,
    category spending, renewal calendar, and subscription-backed category budgets; bank accounts,
    transactions, investments, debt, tax, goals, and sync remain later privacy-reviewed work
23. 🚧 **Window Switcher foundation/prototype** — contracts, in-memory adapters, a 28-field settings
    schema, original presentation work, and deterministic tests exist, but the production runtime is
    unregistered and disabled. Apple's
    [App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
    makes the needed cross-application assistive Accessibility/termination boundary incompatible
    with sandboxed Commandly. A separately signed non-sandboxed companion or disabling App Sandbox
    for direct distribution requires a new
    explicit architecture, security, and distribution decision; neither is currently authorized.
24. ✅ **Markdown Preview foundation** — original registered reader, dependency-free safe renderer,
    schema-driven appearance/rendering/navigation settings, bounded local images, search/source/
    outline/reload/HTML/PDF/print workflows, and a sandboxed Finder Quick Look extension; signed
    Finder registration and release-matrix validation remain distribution work

Do not implement later phases under the guise of foundation work.
