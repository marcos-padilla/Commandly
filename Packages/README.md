# CommandlyPackages

Local Swift package hosting Commandly’s reusable modules.

See `Package.swift` for products and `docs/ARCHITECTURE.md` for dependency rules.

`AIKit` owns vendor-neutral provider/model identifiers, redacted credentials, normalized
conversation and tool values, injectable HTTP transport, and the explicit reviewed provider
adapters. It has no package dependency on the Commandly app target, SearchKit, AppKit, Keychain, or
filesystem services. Finder authorization, opaque file handles, local approvals, Keychain storage,
non-secret connection preferences, and SwiftUI presentation remain in the app target.

The initial provider catalog is explicit: OpenAI, Anthropic, Google Gemini, Mistral AI, Groq, xAI,
OpenRouter, and loopback-only Ollama. Every listed adapter supports the initial non-streaming text
and client-tool runtime. Wire-format similarity is not permission to present an unreviewed service
as supported.

Do not add third-party dependencies during the foundation phase.
