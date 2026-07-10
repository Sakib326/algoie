# Testing

Test strategy, verification, and how to run tests.

---

## Verification Script

The primary Day 1 verification is `priv/repo/seeds/verify_day1.exs`. It tests the complete provisioning and authorization flow.

### Running

```bash
mix run priv/repo/seeds/verify_day1.exs
```

**Note:** The script requires a clean database. Drop and recreate before running:

```bash
mix ecto.drop && mix ecto.create && mix ash.migrate && mix run priv/repo/seeds/verify_day1.exs
```

### What It Tests

1. Tenant provisioning (schema creation, migrations, resource creation)
2. StoreRegistry entry creation
3. Owner membership creation
4. Cross-store access denial
5. Owner-only action denial
6. Owner read permissions
7. Owner destroy permissions (with cascade)
8. Subdomain routing resolution

---

## Unit Tests

The default Phoenix test suite runs via `mix test`. Currently includes 5 basic tests.

---

## Running All Checks

```bash
mix precommit
```

This runs: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`.

---

## Test Strategy

| Test Type | Status | Purpose |
|-----------|--------|---------|
| Verification script | ✓ Complete | End-to-end provisioning and authorization |
| Unit tests | Basic | Phoenix default tests |
| Integration tests | Planned | Multi-step flows across resources |
| Policy tests | Planned | Individual policy check verification |
| Provisioning tests | Planned | Edge cases in tenant creation |

---

## Edge Cases Not Yet Covered

- Provisioning failure mid-way (schema orphaned)
- Concurrent slug creation
- Store deletion with active staff
- User deletion with staff memberships
- Multiple stores with same slug (global uniqueness)
