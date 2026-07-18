# Changelog

All notable changes to Commandly will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Configurable, icon-only Command Wheel profiles with hold-and-release or toggle activation, radial
  pointer selection, keyboard navigation, submenus, recent/frequent command providers, context
  rules, multi-display placement, and accessible adaptive presentation
- Command Wheel settings for profile/page/slot editing, shared command and installed-application
  search with native app icons, typed arguments, shortcuts, placement and interaction preferences,
  import/export, validation, and defaults
- Shared typed command invocation, resolution, execution, availability, and privacy-safe usage
  history across launcher search, registered-application hotkeys, installed applications, and
  Command Wheel
- Versioned atomic Command Wheel profile persistence with migration, collision-safe imports, and
  unavailable-command preservation
- Unified Carbon global-shortcut ownership with press/release generations and no global keyboard
  monitor or new Accessibility requirement
- Command Wheel user, architecture, extension, testing, in-app, privacy, accessibility, and
  performance documentation
- Project foundation for a native macOS SwiftUI application
- Local Swift package modules: AppCore, CommandKit, SearchKit, DesignSystem, Infrastructure, Persistence, SecurityKit, ExtensionKit, Observability
- Composition root, placeholder root scene, settings stub
- Build/test/lint scripts and `make verify`
- Architecture and agent documentation (`AGENTS.md`, `docs/`)
