# Architectural Decisions

Every significant architectural decision, with context and rationale.

---

## Decision 1: Schema-Based Multi-Tenancy

**Decision:** Use PostgreSQL schema-per-tenant isolation via AshPostgres `context` strategy.

**Context:** The platform serves multiple merchants. Each merchant's data (products, orders, customers) must be completely isolated. Row-level isolation (shared tables with `tenant_id` columns) was considered but rejected.

**Alternatives considered:**
- **Row-level isolation** (`tenant_id` column on every table): Simpler queries, easier cross-tenant analytics, but risk of data leakage through bugs in query filters.
- **Database-per-tenant**: Maximum isolation, but operational overhead scales linearly with tenants.
- **Schema-per-tenant** (chosen): Strong isolation at the Postgres level. No query can escape its schema. Moderate operational complexity.

**Trade-offs:** Schema proliferation as tenants grow. Each new tenant creates a schema + runs migrations. Schema cleanup for deleted tenants is not yet implemented.

**Future impact:** All tenant-scoped resources must have `multitenancy strategy(:context)`. The `tenant:` parameter must be the schema name string, not a UUID.

**ADR:** [001-schema-multitenancy.md](ADR/001-schema-multitenancy.md)

---

## Decision 2: StoreRegistry for Subdomain Routing

**Decision:** Use a public-schema table to map slugs to tenant IDs, enabling cross-tenant slug lookups.

**Context:** Subdomain routing (e.g., `nike.algoie.com`) requires looking up a store by slug. Since tenant schemas are isolated, you can't query across schemas to find a store. A public-schema routing table solves this.

**Alternatives considered:**
- **Shared slug table with tenant_id column** (chosen): Simple, efficient, single query for routing.
- **DNS-level routing**: Requires DNS provider integration, not flexible enough.
- **Application-level cache**: Adds complexity and consistency concerns.

**Trade-offs:** The registry must be kept in sync with Store creation/deletion. The current `after_action` hook handles creation, but deletion cleanup is deferred.

**ADR:** [002-store-registry.md](ADR/002-store-registry.md)

---

## Decision 3: StoreStaff as Internal Resource

**Decision:** StoreStaff uses `always()` policies and is not exposed through APIs.

**Context:** StoreStaff is a join table between Users and Stores. Exposing it directly would create circular authorization issues (StoreStaff policy checking StoreStaff to authorize Store operations).

**Alternatives considered:**
- **Expose with strict policies**: Would require complex policy composition and risk circular authorization.
- **Internal with `always()`** (chosen): Schema isolation handles tenant separation. Parent Store policy handles access control.

**Trade-offs:** Future staff management APIs will need to replace the `always()` policies with proper authorization.

**ADR:** [003-storestaff-internal.md](ADR/003-storestaff-internal.md)

---

## Decision 4: Schema Name as Tenant Context

**Decision:** Pass `"tenant_<uuid>"` as the tenant value, not the raw UUID.

**Context:** AshPostgres's `context` strategy uses the tenant value directly as the Postgres schema name via `Ecto.Query.put_query_prefix/2`.

**Alternatives considered:**
- **Pass raw UUID**: Would fail because the schema is named `"tenant_<uuid>"`, not just the UUID.
- **Implement `Ash.ToTenant` protocol**: Could convert UUID to schema name, but adds indirection.
- **Pass schema name directly** (chosen): Simple, direct, matches what the data layer expects.

**Trade-offs:** The schema name includes a prefix, making it slightly longer. But this is a minor concern.

---

## Decision 4: Store Authorization Boundary

**Decision:** Store policies are the primary authorization boundary. StoreStaff policies are permissive.

**Context:** Every request flows through Store policies. StoreStaff policies exist but use `always()` because:
1. Schema isolation already prevents cross-tenant access
2. Parent Store policy controls who can access a specific store

**Alternatives considered:**
- **StoreStaff as the authorization boundary**: Would require setting `store_id` context for every operation, and risk circular authorization.
- **Store as the boundary** (chosen): Cleaner, simpler, no circular auth issues.

---

## Decision 5: `after_action` for StoreRegistry Creation

**Decision:** Use Ash's `after_action` builtin to create StoreRegistry entries when a Store is created.

**Context:** StoreRegistry entries must be created only when Store creation succeeds. They must be created within the same transaction.

**Alternatives considered:**
- **Manual call in provisioner**: Would work for provisioning but miss direct `Ash.create(Store, ...)` calls.
- **`after_action` builtin** (chosen): Automatically creates the entry for any successful Store creation, regardless of caller.

**Trade-offs:** The `after_action` callback must use Ecto directly (with `prefix: "public"`) to bypass tenant context propagation.

---

## Decision 6: `cascade_destroy` for Store Staff

**Decision:** Use `cascade_destroy(:staff_memberships, after_action?: false)` on the Store destroy action.

**Context:** When a Store is destroyed, its StoreStaff records must also be destroyed. PostgreSQL FK constraints prevent deleting a Store with existing StoreStaff records.

**Alternatives considered:**
- **Deferrable FK constraints**: Requires database schema changes and adds complexity.
- **`cascade_destroy` with `after_action?: false`** (chosen): Deletes children before the parent. No deferrable constraints needed. Fires Ash lifecycle hooks on StoreStaff.

**Trade-offs:** The destroy action becomes non-atomic (`require_atomic?(false)`), which means it can't be used in atomic bulk operations.

---

## Decision 7: Ash Over Custom Ecto

**Decision:** Use Ash resources, actions, and policies instead of custom Ecto schemas and context modules.

**Context:** Ash provides declarative resource definitions, built-in policy evaluation, lifecycle hooks, and data layer abstraction. Writing custom Ecto schemas would require reimplementing these features.

**Alternatives considered:**
- **Custom Ecto schemas with context modules**: More control, but requires manual policy enforcement, manual lifecycle hooks, manual query building.
- **Ash resources** (chosen): Declarative, well-tested, integrates with AshAuthentication and AshPostgres.

**Trade-offs:** Ash has a learning curve. Some behaviors (like `after_action` arity, `primary?` on actions) are not obvious without reading the source.

---

## Decision 8: Ecto for StoreRegistry Operations

**Decision:** Use Ecto directly (with `prefix: "public"`) for StoreRegistry create/read/delete, bypassing Ash.

**Context:** Ash's tenant context propagation would route StoreRegistry operations to the tenant schema, but StoreRegistry must live in the public schema. Ash's `set_tenant` doesn't work reliably for this use case within after_action hooks.

**Alternatives considered:**
- **Ash with `set_tenant(nil)`**: Was attempted but failed because the context propagates within the transaction.
- **Ash with `authorize?: false`**: Still routes to the wrong schema.
- **Ecto with `prefix: "public"`** (chosen): Direct, reliable, explicit.

**Trade-offs:** Bypasses Ash's lifecycle hooks and policy evaluation for StoreRegistry. Acceptable because StoreRegistry is an internal routing table.
