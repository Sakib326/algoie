# ADR 003: StoreStaff as Internal Resource

**Status:** Accepted

## Context

StoreStaff is a join table between Users and Stores, linking a user to a store with a role (owner/staff). Exposing it directly through APIs would create circular authorization issues: StoreStaff's policy would need to check Store access to authorize Store operations, but Store's policy already checks StoreStaff.

## Decision

StoreStaff is an internal resource with intentionally permissive `always()` policies. It is documented with an `@moduledoc` warning that it must not be exposed through APIs without replacing the policies.

## Consequences

- **No circular authorization:** Store policies control access. StoreStaff policies are permissive.
- **Schema isolation provides tenant separation:** The `always()` policies are safe because Postgres schema isolation prevents cross-tenant access.
- **Future work required:** When staff management APIs are built, the `always()` policies must be replaced with explicit authorization rules.

## Alternatives Considered

- **Expose with strict policies:** Would require complex policy composition and risk circular authorization.
