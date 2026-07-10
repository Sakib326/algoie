# ADR 002: StoreRegistry for Subdomain Routing

**Status:** Accepted

## Context

Subdomain routing (e.g., `nike.algoie.com`) requires looking up a store by slug. Since tenant schemas are isolated, you cannot query across schemas to find a store by slug.

## Decision

Use a public-schema table (`store_registry`) that maps slugs to tenant IDs. This table is queried directly via Ecto (not Ash) to bypass tenant context propagation.

## Consequences

- **Single query for routing:** The `StoreSlugPlug` performs one query to resolve a subdomain to a store.
- **Sync requirement:** The registry must be kept in sync with Store creation/deletion. The `after_action` hook handles creation; deletion cleanup is deferred.
- **Ecto bypass:** StoreRegistry operations use Ecto directly with `prefix: "public"` because Ash's tenant context would route them to the wrong schema.

## Alternatives Considered

- **DNS-level routing:** Requires DNS provider integration, less flexible.
- **Application-level cache:** Adds complexity and consistency concerns.
