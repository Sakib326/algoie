# Algoie

A multi-tenant ecommerce SaaS platform built with Elixir, Phoenix, and Ash Framework.

## What is Algoie?

Algoie is a production-ready multi-tenant ecommerce platform where one Tenant owns many Stores. Each tenant's data is isolated via PostgreSQL schemas. The architecture is designed for scale: adding a new tenant creates a new schema, not new rows in a shared table.

## Tech Stack

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

## Current Progress

Day 1 is complete. The foundation includes multi-tenancy, store hierarchy, authentication, authorization, provisioning, and subdomain routing.

See [ROADMAP.md](ROADMAP.md) for the full roadmap.

## Quick Start

```bash
mix deps.get
mix ecto.setup
mix assets.setup
mix assets.build
mix phx.server
```

## Documentation

| Document | Purpose |
|----------|---------|
| [AGENT_CONTEXT.md](AGENT_CONTEXT.md) | **Read this first.** Project state, architecture, rules for agents |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Deep architectural reference with diagrams |
| [DATABASE.md](DATABASE.md) | Schema design, tables, relationships, migrations |
| [SECURITY.md](SECURITY.md) | Authentication, authorization, threat model |
| [TESTING.md](TESTING.md) | Test strategy and verification |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development workflow and standards |
| [ROADMAP.md](ROADMAP.md) | Project milestones and future work |
| [DECISIONS.md](DECISIONS.md) | Architectural decisions with rationale |
| [ADR/](ADR/) | Architecture Decision Records (one per decision) |
| [DAY1_FOUNDATION.md](DAY1_FOUNDATION.md) | Day 1 historical record |

### Where to Start

1. **New developer or AI agent?** Read [AGENT_CONTEXT.md](AGENT_CONTEXT.md).
2. **Need architecture details?** Read [ARCHITECTURE.md](ARCHITECTURE.md).
3. **Working with the database?** Read [DATABASE.md](DATABASE.md).
4. **Contributing code?** Read [CONTRIBUTING.md](CONTRIBUTING.md).
5. **Making decisions?** Check [DECISIONS.md](DECISIONS.md) and [ADR/](ADR/).
