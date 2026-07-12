# ADR-0002: Dependency injection via composition root

## Status

Accepted

## Context

Services such as persistence, permissions, and logging must be replaceable in tests without global mutable singletons or a DI framework.

## Decision

Use initializer-based dependency injection assembled in `Commandly/Composition` (`AppBootstrapper`, `AppDependencies`, `AppContainer`).

No third-party DI container.

## Consequences

- Explicit dependencies
- Easy test doubles
- Composition code grows with features (acceptable; keep factories focused)
