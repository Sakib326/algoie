# Day 1 Foundation

Historical record of what was built in Day 1.

---

## Goals

Establish the multi-tenant foundation: schema isolation, store hierarchy, authentication, authorization, provisioning, and subdomain routing.

## Completed Work

| Area | Status | Notes |
|------|--------|-------|
| Ash domains (Accounts, Stores) | ✓ | Two domains with clean separation |
| Domain resources (6 resources) | ✓ | Tenant, User, Token, Store, StoreRegistry, StoreStaff |
| Ash policies (4 checks) | ✓ | ActorIsSystem, ActorHasStoreAccess, ActorHasAnyStoreAccess, ActorIsRecordOwner |
| Authentication foundation | ✓ | Password strategy with `register_action_accept` |
| Tenant provisioning | ✓ | Schema + migrations + Store + User + StoreStaff |
| Subdomain routing | ✓ | StoreSlugPlug resolves slugs via StoreRegistry |
| StoreRegistry | ✓ | Public-schema slug→tenant mapping |
| Verification script | ✓ | 14/14 checks passing |

## Changes from Original Plan

### 1. Schema name as tenant context

The plan specified `tenant: tenant.id` (UUID). The implementation uses `tenant: "tenant_<uuid>"` (schema name).

**Why:** AshPostgres's `context` strategy passes the tenant value directly to `Ecto.Query.put_query_prefix/2` as the Postgres schema name. Passing a raw UUID would fail because the schema is named `"tenant_<uuid>"`.

### 2. Two-step user registration eliminated

The plan called for `register_with_password` then `Ash.update` to set the name. The implementation uses `register_action_accept([:name])` to accept `name` during registration.

**Why:** AshAuthentication provides a first-class DSL option for this. No workaround needed.

### 3. `cascade_destroy` instead of raw SQL cascade

The plan used raw SQL for cascading deletes. The implementation uses Ash's built-in `cascade_destroy` change.

**Why:** `cascade_destroy` with `after_action?: false` deletes children before the parent, avoiding deferrable FK constraints while still firing Ash lifecycle hooks.

### 4. `after_action` hook uses 3-argument callback

The original plan used a 2-argument callback. Ash 3.29's `after_action` builtin passes 3 arguments: `(changeset, result, context)`.

**Why:** Discovered during implementation. The `lift_functions` macro wraps the callback, and the entity's `change/3` function calls it with 3 args.

### 5. `Ash.read_one` instead of raw SQL in `ActorHasStoreAccess`

The original implementation used `Ecto.Adapters.SQL.query` for the store_staff lookup in policy checks. This failed during destroy operations because `Ecto.Adapters.SQL.query` can't checkout a new connection inside Ash's authorization flow.

**Why:** `Ash.read_one(..., authorize?: false)` reuses the current connection and works correctly within Ash transactions.

### 6. StoreRegistry operations bypass Ash

The plan used Ash to manage StoreRegistry. The implementation uses Ecto directly with `prefix: "public"`.

**Why:** Ash's tenant context propagation would route StoreRegistry operations to the wrong schema. Direct Ecto operations bypass this.

### 7. Token signing secret not yet runtime-configured

The plan included runtime JWT configuration. Tokens are disabled for Day 1, so the secret remains in compile-time config.

**Why:** Tokens are Day 2 work. The secret will be moved to environment variables then.

## Problems Encountered

### Ash version compatibility

Several features required adaptation for Ash 3.29 / AshAuthentication 4.14:
- `after_action` requires the `change` keyword prefix
- `after_action` callbacks accept 3 arguments, not 2
- `password_confirmation_required?` is now `confirmation_required?`
- `signing_algorithm` expects a string (`"HS256"`), not an atom (`:hs256`)
- `register_action_accept` is the DSL option for extending register actions
- `authorizers: [Ash.Policy.Authorizer]` is required on all resources with policies
- `primary?(true)` is required on explicit actions
- `require_atomic?(false)` is required for destroy actions with non-atomic changes
- `cascade_destroy` is a change, not a relationship option

### Database management

The `mix ecto.drop` command had issues during development due to stale BEAM VM connections. The verification script uses `Ecto.Adapters.SQL.query` to clear data between runs instead.

### Policy check connection issues

`Ecto.Adapters.SQL.query` failed inside Ash authorization flows. Switching to `Ash.read_one(..., authorize?: false)` resolved this.

## Current Project State

- 28 Elixir source files
- 3 migration files
- 1 verification script
- All `mix precommit` checks passing
- 5 unit tests passing
- 14 verification checks passing

---

## See Also

- [AGENT_CONTEXT.md](AGENT_CONTEXT.md) — Current project state
- [ARCHITECTURE.md](ARCHITECTURE.md) — Architecture reference
- [ROADMAP.md](ROADMAP.md) — What comes next
