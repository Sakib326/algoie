# Architectural Decisions

Chronological index of significant architectural decisions. Each decision has a detailed ADR in the [ADR/](ADR/) folder.

---

## Decision 1: Schema-Based Multi-Tenancy

Use PostgreSQL schema-per-tenant isolation via AshPostgres `context` strategy.

Each tenant gets a dedicated schema named `tenant_<uuid>`. The `tenant:` parameter must be the schema name string, not a UUID. Tenant and StoreRegistry live in the `public` schema.

**Alternatives considered:** Row-level isolation (simpler queries, higher leakage risk), database-per-tenant (maximum isolation, doesn't scale operationally).

**ADR:** [001-schema-multitenancy.md](ADR/001-schema-multitenancy.md)

---

## Decision 2: StoreRegistry for Subdomain Routing

Use a public-schema table to map slugs to tenant IDs, enabling cross-tenant slug lookups.

StoreRegistry operations use Ecto directly (not Ash) because Ash's tenant context propagation would route them to the wrong schema.

**Alternatives considered:** DNS-level routing, application-level cache.

**ADR:** [002-store-registry.md](ADR/002-store-registry.md)

---

## Decision 3: StoreStaff as Internal Resource

StoreStaff uses `always()` policies and is not exposed through APIs.

Schema isolation handles tenant separation. Parent Store policies handle access control. Exposing it directly would create circular authorization issues.

**Alternatives considered:** Expose with strict policies (complex composition, circular auth risk).

**ADR:** [003-storestaff-internal.md](ADR/003-storestaff-internal.md)

---

## Decision 4: Schema Name as Tenant Context

Pass `"tenant_<uuid>"` as the tenant value, not the raw UUID.

AshPostgres's `context` strategy uses the tenant value directly as the Postgres schema name via `Ecto.Query.put_query_prefix/2`.

**Alternatives considered:** Pass raw UUID (fails), implement `Ash.ToTenant` protocol (adds indirection).

**ADR:** [001-schema-multitenancy.md](ADR/001-schema-multitenancy.md)

---

## Decision 5: Store Authorization Boundary

Store policies are the primary authorization boundary. StoreStaff policies are permissive.

Every request flows through Store policies. StoreStaff uses `always()` because schema isolation prevents cross-tenant access and parent Store policy controls store-level access.

**Alternatives considered:** StoreStaff as the authorization boundary (circular auth risk, requires `store_id` context on every operation).

**ADR:** [004-authorization-model.md](ADR/004-authorization-model.md)

---

## Decision 6: `after_action` for StoreRegistry Creation

Use Ash's `after_action` builtin to create StoreRegistry entries when a Store is created.

The `after_action` callback uses Ecto directly (with `prefix: "public"`) to bypass tenant context propagation. Automatically creates the entry for any successful Store creation, regardless of caller.

**Alternatives considered:** Manual call in provisioner (misses direct `Ash.create` calls).

**ADR:** [002-store-registry.md](ADR/002-store-registry.md)

---

## Decision 7: `cascade_destroy` for Store Staff

Use `cascade_destroy(:staff_memberships, after_action?: false)` on the Store destroy action.

Deletes children before the parent. No deferrable FK constraints needed. Fires Ash lifecycle hooks on StoreStaff. The destroy action becomes non-atomic (`require_atomic?(false)`).

**Alternatives considered:** Deferrable FK constraints (requires schema changes).

**ADR:** [005-tenant-provisioning.md](ADR/005-tenant-provisioning.md)

---

## Decision 8: Ash Over Custom Ecto

Use Ash resources, actions, and policies instead of custom Ecto schemas and context modules.

Ash provides declarative resource definitions, built-in policy evaluation, lifecycle hooks, and data layer abstraction. Integrates natively with AshAuthentication and AshPostgres.

**Alternatives considered:** Custom Ecto schemas with context modules (more control, requires manual policy enforcement).

**ADR:** [008-domain-boundaries.md](ADR/008-domain-boundaries.md)

---

## Decision 9: Ecto for StoreRegistry Operations

Use Ecto directly (with `prefix: "public"`) for StoreRegistry create/read/delete, bypassing Ash.

Ash's tenant context propagation would route StoreRegistry operations to the tenant schema. Direct Ecto operations bypass this reliably.

**Alternatives considered:** Ash with `set_tenant(nil)` (failed within transactions), Ash with `authorize?: false` (still wrong schema).

**ADR:** [002-store-registry.md](ADR/002-store-registry.md)

---

## Decision 10: Domain Boundaries

Two Ash domains:
- **`Algoie.Accounts`**: Tenant, User, Token, StoreStaff — people and access
- **`Algoie.Stores`**: Store, StoreRegistry — business entities

StoreStaff lives in Accounts because it's primarily about access control. StoreRegistry lives in Stores despite being a routing table.

**Alternatives considered:** Single domain (mixes concerns), three domains (over-engineered for Day 1).

**ADR:** [008-domain-boundaries.md](ADR/008-domain-boundaries.md)

---

## Decision 11: Tenant Provisioning

Sequential provisioning flow outside of Ecto transactions for schema creation/migration, followed by Ash resource creation.

Schema creation cannot run inside a Postgres transaction with rollback support. If resource creation fails, the orphaned schema is dropped.

**Alternatives considered:** Wrap everything in a single transaction (not possible due to DDL limitations).

**ADR:** [005-tenant-provisioning.md](ADR/005-tenant-provisioning.md)

---

## Decision 12: Authentication Strategy

Use AshAuthentication's password strategy with `register_action_accept([:name])` to extend the auto-generated register action. Tokens configured but disabled for Day 1.

**Alternatives considered:** Custom auth with Comeonin/Bcrypt, Auth0/third-party SaaS.

**ADR:** [006-authentication-strategy.md](ADR/006-authentication-strategy.md)

---

## Decision 13: Routing Strategy

Use a Phoenix plug (`StoreSlugPlug`) that extracts the subdomain from the host, looks it up in StoreRegistry, and sets the Ash tenant context and store_id.

**Alternatives considered:** DNS-level routing, middleware-based routing.

**ADR:** [007-routing-strategy.md](ADR/007-routing-strategy.md)
