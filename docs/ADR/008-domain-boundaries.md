# ADR 008: Domain Boundaries

**Status:** Accepted

## Context

The system needs clear separation between business concerns: authentication/tenancy vs. store operations.

## Decision

Two Ash domains:
- **`Algoie.Accounts`**: Tenant, User, Token, StoreStaff
- **`Algoie.Stores`**: Store, StoreRegistry

## Consequences

- **Clear responsibility:** Accounts handles people and access. Stores handles business entities.
- **StoreStaff in Accounts:** StoreStaff is a join table that belongs to both domains, but lives in Accounts because it's primarily about access control.
- **StoreRegistry in Stores:** Despite being a routing table, it's logically about stores.

## Alternatives Considered

- **Single domain:** Would work but mixes concerns and makes the domain modules larger.
- **Three domains** (Accounts, Stores, Routing): Over-engineered for Day 1.
