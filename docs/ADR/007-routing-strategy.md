# ADR 007: Routing Strategy

**Status:** Accepted

## Context

Stores are accessed via subdomains (e.g., `nike.algoie.com`). The system must resolve a subdomain to the correct tenant and store.

## Decision

Use a Phoenix plug (`StoreSlugPlug`) that extracts the subdomain from the host, looks it up in StoreRegistry (public schema), and sets the Ash tenant context and store_id in the request context.

## Consequences

- **Single lookup per request:** One query resolves the subdomain to tenant + store.
- **Ash context propagation:** The plug sets `tenant:` and `store_id:` via `Ash.PlugHelpers`, which Ash uses for query routing and policy evaluation.
- **404 for unknown slugs:** Unknown subdomains return a clean 404 response.

## Alternatives Considered

- **DNS-level routing:** Requires DNS provider integration, not flexible enough.
- **Middleware-based routing:** Would require checking roles on every request.
