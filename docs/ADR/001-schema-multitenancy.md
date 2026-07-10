# ADR 001: Schema-Based Multi-Tenancy

**Status:** Accepted

## Context

Algoie serves multiple merchants. Each merchant's data (products, orders, customers) must be completely isolated. The platform uses PostgreSQL as its database.

## Decision

Use PostgreSQL schema-per-tenant isolation via AshPostgres's `context` multitenancy strategy.

Each tenant gets a dedicated schema named `tenant_<uuid>`. All tenant-scoped resources (Store, User, StoreStaff) live in this schema. The `tenant:` parameter passed to Ash functions must be the schema name string (e.g., `"tenant_abc123"`), not the raw UUID.

The Tenant resource and StoreRegistry live in the `public` schema because they must be accessible cross-tenant.

## Consequences

- **Strong isolation:** No query can accidentally cross tenant boundaries. The Postgres schema prefix enforces this at the database level.
- **Operational complexity:** Each new tenant creates a schema and runs migrations. Schema cleanup for deleted tenants requires additional tooling.
- **Tenant value must be a schema name:** AshPostgres passes the tenant value directly to `Ecto.Query.put_query_prefix/2`. Passing a raw UUID would fail.

## Alternatives Considered

- **Row-level isolation** (`tenant_id` column): Simpler queries but higher risk of data leakage.
- **Database-per-tenant:** Maximum isolation but doesn't scale operationally.

## References

- AshPostgres multitenancy documentation
- PostgreSQL schema documentation
