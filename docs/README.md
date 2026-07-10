# Algoie — Documentation

A multi-tenant ecommerce SaaS platform built with Elixir, Phoenix, and Ash Framework.

## Project Overview

Algoie is a production-ready multi-tenant ecommerce platform where one Tenant owns many Stores. Each tenant's data is isolated via PostgreSQL schemas. The architecture is designed for scale: adding a new tenant creates a new schema, not new rows in a shared table.

## Documentation Structure

| Document | Purpose | Audience |
|----------|---------|----------|
| [AGENT_CONTEXT.md](AGENT_CONTEXT.md) | **Read this first.** Project vision, architecture, rules for agents | AI agents, new developers |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Deep architectural reference with diagrams | Developers, architects |
| [DAY1_FOUNDATION.md](DAY1_FOUNDATION.md) | What was built in Day 1 and why | Anyone reviewing Day 1 |
| [ROADMAP.md](ROADMAP.md) | Project milestones and future work | Project planning |
| [DECISIONS.md](DECISIONS.md) | All architectural decisions with rationale | Developers, reviewers |
| [ADR/](ADR/) | Architecture Decision Records (one per decision) | Detailed decision history |
| [DATABASE.md](DATABASE.md) | Schema design, tables, migrations | Database work |
| [SECURITY.md](SECURITY.md) | Authentication, authorization, threat model | Security review |
| [TESTING.md](TESTING.md) | Test strategy and verification | QA, developers |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development workflow and standards | Contributors |

## Where to Start

1. **New developer or AI agent?** Read [AGENT_CONTEXT.md](AGENT_CONTEXT.md) first. It explains the project vision, architecture, and rules.
2. **Need implementation details?** Read [ARCHITECTURE.md](ARCHITECTURE.md) for diagrams and resource-by-resource breakdown.
3. **Reviewing Day 1?** Read [DAY1_FOUNDATION.md](DAY1_FOUNDATION.md).
4. **Making decisions?** Check [DECISIONS.md](DECISIONS.md) and the [ADR/](ADR/) folder.
5. **Working with the database?** Read [DATABASE.md](DATABASE.md).
6. **Contributing code?** Read [CONTRIBUTING.md](CONTRIBUTING.md).

## Reading Order

For comprehensive understanding, read in this order:

```
AGENT_CONTEXT.md  →  ARCHITECTURE.md  →  DAY1_FOUNDATION.md  →  DECISIONS.md  →  ADR/  →  ROADMAP.md
```

For quick reference, jump directly to the relevant section in ARCHITECTURE.md.
