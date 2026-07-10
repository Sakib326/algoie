# ADR 005: Tenant Provisioning

**Status:** Accepted

## Context

When a new merchant signs up, the system must create a complete tenant: database schema, default store, owner account, and staff membership.

## Decision

Use a sequential provisioning flow outside of Ecto transactions for schema creation/migration, followed by Ash resource creation for each entity.

Schema creation and migration run outside any Ecto transaction because Postgres DDL cannot run inside a transaction in a way that allows rollback. Resource creation (Store, User, StoreStaff) happens after migration completes.

If any resource creation step fails, the orphaned schema is dropped via `drop_tenant_schema`.

## Consequences

- **Schema is permanent once created:** If resource creation fails after migration, the schema exists but has no data. The cleanup function drops it.
- **No rollback of schema creation:** This is a Postgres limitation. DDL statements are transactional, but schema creation in Ash transactions can cause issues.
- **Sequential resource creation:** Each resource is created in its own Ash transaction, allowing individual failure handling.

## Alternatives Considered

- **Wrap everything in a single transaction:** Not possible because schema creation cannot run inside a Postgres transaction with rollback support.
