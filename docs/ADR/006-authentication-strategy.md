# ADR 006: Authentication Strategy

**Status:** Accepted

## Context

The platform needs user authentication. AshAuthentication provides a password strategy that integrates natively with Ash resources.

## Decision

Use AshAuthentication's password strategy with `register_action_accept([:name])` to extend the auto-generated register action. Tokens are configured but disabled for Day 1.

## Consequences

- **Native integration:** Authentication actions are generated automatically by the framework.
- **Extended registration:** `register_action_accept([:name])` allows accepting the `name` field during registration without a two-step process.
- **Tokens deferred:** JWT tokens are configured (`enabled?: false`) but not active. Token signing secret remains in compile-time config until Day 2.

## Alternatives Considered

- **Custom auth with Comeonin/Bcrypt:** More control but requires reimplementing token management, session handling, etc.
- **Auth0/第三方 SaaS:** Adds external dependency and cost.
