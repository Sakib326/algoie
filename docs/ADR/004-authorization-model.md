# ADR 004: Authorization Model

**Status:** Accepted

## Context

The platform needs fine-grained access control: owners can do everything, staff can read/update stores, and users can only access their own profiles.

## Decision

Use Ash's built-in policy system with `SimpleCheck` modules. Store policies are the primary authorization boundary. StoreStaff policies are permissive (`always()`) because schema isolation handles tenant separation and Store policies handle store-level access.

## Consequences

- **Declarative policies:** Authorization rules are defined on resources, not scattered across context modules.
- **No circular authorization:** StoreStaff uses `always()` to break the cycle where StoreStaff policy would check Store access.
- **`authorize?: false` for internal queries:** `ActorHasStoreAccess` and `ActorHasAnyStoreAccess` use `authorize?: false` to avoid triggering StoreStaff's policies during their own checks.

## Alternatives Considered

- **Custom authorization in context modules:** More control but harder to maintain and audit.
- **Role-based middleware:** Would require checking roles on every request, adding latency.
