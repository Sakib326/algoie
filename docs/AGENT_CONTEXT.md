# Agent Context

**This is the most important document in the repository.** Every AI coding agent and new developer should read this before writing any code.

---

## Project Vision

Algoie is a multi-tenant ecommerce SaaS platform. A single business (Tenant) owns multiple Stores. Each Store can have its own products, orders, customers, and staff.

### Long-term Goals

- A self-serve platform where merchants create a store in minutes
- Subdomain-based storefronts (e.g., `nike.algoie.com`)
- AI-assisted store management
- Multi-channel sales (online, POS, messaging)

### MVP Philosophy

Build incrementally. Each day establishes a foundation layer. Later layers depend on earlier ones but never modify their core contracts. If an earlier decision proves wrong, the architecture is updated to reflect reality — the documentation is the source of truth, not the original plan.

---

## Current Status

Day 1 is complete. The foundation includes: multi-tenancy, store hierarchy, authentication, authorization, provisioning, and routing.

**Implemented:**
- Ash domains (Accounts, Stores)
- All domain resources (Tenant, User, Token, Store, StoreRegistry, StoreStaff)
- Ash policies (ActorIsSystem, ActorHasStoreAccess, ActorHasAnyStoreAccess, ActorIsRecordOwner)
- Authentication foundation (password strategy, token infrastructure)
- Tenant provisioning (Tenant + schema + migrations + default Store + owner User + StoreStaff)
- Subdomain routing (StoreSlugPlug)
- StoreRegistry for slug→tenant resolution
- Verification script (14/14 checks passing)

**Not implemented:**
- Products, inventory, orders, customers
- POS, messaging, AI agent
- Storefront, custom domain SSL
- Dynamic RBAC

---

## Architecture Summary

### Tech Stack

| Technology | Role |
|-----------|------|
| Elixir | Primary language |
| Phoenix | Web framework |
| Ash Framework | Domain modeling, policies, actions |
| AshPostgres | PostgreSQL adapter with schema-per-tenant multitenancy |
| AshAuthentication | Password strategy, JWT tokens |
| PostgreSQL | Database with schema isolation |
| Tailwind CSS | Styling |
| Bandit | HTTP server |

### Hierarchy

Tenant owns Stores. Users are linked to Stores via StoreStaff. Schema-per-tenant isolation ensures data separation.

| Level | Entity | Schema | Purpose |
|-------|--------|--------|---------|
| Cross-tenant | Tenant | `public` | Business entity |
| Cross-tenant | StoreRegistry | `public` | Slug→tenant mapping |
| Cross-tenant | Token | `public` | JWT token storage |
| Per-tenant | User | `tenant_<uuid>` | Authenticated person |
| Per-tenant | Store | `tenant_<uuid>` | Operational unit |
| Per-tenant | StoreStaff | `tenant_<uuid>` | Join table: user ↔ store |

### Two Ash Context Values

Every store request sets two values in the Ash context:

| Key | Set By | Purpose | Example |
|-----|--------|---------|---------|
| `tenant` | StoreSlugPlug | Postgres schema routing | `"tenant_abc123"` |
| `store_id` | StoreSlugPlug | Store-level authorization | `"store-uuid"` |

These are independent — you can be in the right tenant but not have access to a specific store.

### Domains

| Domain | Resources | Responsibility |
|--------|-----------|---------------|
| `Algoie.Accounts` | Tenant, User, Token, StoreStaff | People and access |
| `Algoie.Stores` | Store, StoreRegistry | Business entities |

### Authorization Model

Store policies are the primary authorization boundary. StoreStaff uses permissive `always()` policies because schema isolation handles tenant separation and parent Store policies handle store-level access.

| Resource | Create | Read/Update | Destroy |
|----------|--------|-------------|---------|
| Store | `:system` | `:system` OR `ActorHasAnyStoreAccess` OR `ActorHasStoreAccess:staff` | `:system` OR `ActorHasStoreAccess:owner` |
| User | `:system` | `:system` OR `ActorIsRecordOwner` | — |
| StoreStaff | `:system` | `always()` | `always()` |
| Tenant | `:system` | `:system` | `:system` |

Policy checks avoid circular authorization by using `authorize?: false` on internal queries.

---

## Coding Principles

1. **Follow Ash conventions.** Use Ash resources, actions, and policies. Avoid custom Ecto schemas when Ash resources suffice.
2. **Prefer framework features.** Ash provides multitenancy, policies, lifecycle hooks, and data layer abstraction. Use them.
3. **Avoid custom SQL unless necessary.** Raw SQL is used only for StoreRegistry operations (to bypass tenant context) and policy checks (to avoid circular authorization).
4. **Business logic belongs in resources.** Actions, changes, and policies live on the resource, not in separate context modules.
5. **No premature optimization.** Ash handles query optimization. Profile before optimizing.
6. **Never change architecture without updating documentation.** If the implementation differs from the plan, update the docs to match reality.
7. **If Ash recommends a different approach, follow Ash.** The framework's conventions are battle-tested. When Ash and the original plan conflict, Ash wins.

---

## Rules for AI Agents

1. **Read AGENT_CONTEXT.md and ARCHITECTURE.md before coding.**
2. **Don't refactor working code.** Only change code when there's a clear bug or a documented improvement.
3. **Keep implementation aligned with architecture.** If you change behavior, update the docs.
4. **Explain architectural decisions.** When you make a non-trivial change, document why.
5. **Run `mix precommit` before committing.** This catches formatting, compilation, and test issues.
6. **Don't add dependencies without justification.** Every dependency is a maintenance burden.

---

## Known Limitations

| Limitation | Reason | Status |
|-----------|--------|--------|
| StoreStaff uses `always()` policies | Internal resource; schema isolation handles tenant separation | Intentional — see [ADR/003](ADR/003-storestaff-internal.md) |
| JWT tokens disabled | Day 1 focuses on foundation | Planned for Day 2 |
| Dynamic RBAC postponed | Requires product/order domain first | Future phase |
| Storefront not implemented | Depends on product catalog | Future phase |
| No soft deletes | Hard deletes with cascade | Future phase |
| No audit logging | Observability layer comes after core features | Future phase |
| Token signing secret hardcoded | Tokens are disabled | Planned for Day 2 |

---

## Next Milestone: Day 2

Day 2 builds on the Day 1 foundation:

- **Product catalog:** Products, categories, variants, images
- **Inventory management:** Stock tracking, low-stock alerts
- **Basic storefront:** Public product browsing per store
- **JWT token configuration:** Enable tokens with proper secret management
- **Staff management APIs:** Expose StoreStaff with proper authorization

See [ROADMAP.md](ROADMAP.md) for the full roadmap.

---

## Deeper Documentation

| Topic | Document |
|-------|----------|
| System architecture, request lifecycle, resource details | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Database schemas, tables, relationships, migrations | [DATABASE.md](DATABASE.md) |
| Authentication, authorization, isolation, threat model | [SECURITY.md](SECURITY.md) |
| Test strategy and verification | [TESTING.md](TESTING.md) |
| Development workflow and standards | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Project roadmap | [ROADMAP.md](ROADMAP.md) |
| Decision index and ADRs | [DECISIONS.md](DECISIONS.md), [ADR/](ADR/) |
| Day 1 historical record | [DAY1_FOUNDATION.md](DAY1_FOUNDATION.md) |
