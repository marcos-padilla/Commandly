# ADR-0001: Modular architecture via local Swift packages

## Status

Accepted

## Context

Commandly needs clear boundaries so app UI, domain contracts, and system integrations can evolve independently and remain testable.

## Decision

Use a local Swift package (`Packages/`) with focused library products:

AppCore, CommandKit, SearchKit, DesignSystem, Infrastructure, Persistence, SecurityKit, ExtensionKit, Observability.

The macOS app target depends on these products and performs composition.

## Consequences

- Enforced one-directional dependencies
- Faster, isolated package tests
- Slightly more wiring in Xcode / Package.swift when adding modules
