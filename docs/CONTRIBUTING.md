# Contributing

Development workflow, standards, and expectations.

---

## Environment Setup

```bash
# Install dependencies
mix deps.get

# Set up database
mix ecto.setup

# Install asset tools
mix assets.setup

# Build assets
mix assets.build
```

---

## Coding Standards

### Elixir/Phoenix

- Follow the Elixir style guide
- Use `mix format` for formatting (run automatically via `mix precommit`)
- Use `mix credo` for static analysis

### Ash Framework

- Use Ash resources instead of custom Ecto schemas
- Use Ash actions instead of custom context functions
- Use Ash policies instead of custom authorization logic
- Follow Ash naming conventions (resource names are singular, domain names are plural)

### Documentation

- Add `@moduledoc` to public modules
- Add `@doc` to public functions
- Update documentation when changing architecture
- See [docs/README.md](docs/README.md) for the documentation structure

---

## Pre-commit Checks

```bash
mix precommit
```

This runs:
1. `compile --warnings-as-errors` — no compilation warnings
2. `deps.unlock --unused` — no unused dependencies
3. `format` — consistent formatting
4. `test` — all tests pass

---

## Commit Conventions

- Use conventional commit messages: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`
- Keep commits focused on a single change
- Reference issues when applicable

---

## Pull Request Expectations

- All `mix precommit` checks pass
- Documentation updated if architecture changed
- New resources include policies
- New features include verification or tests
- No breaking changes without migration plan

---

## See Also

- [AGENT_CONTEXT.md](AGENT_CONTEXT.md) — Coding principles and rules
- [ARCHITECTURE.md](ARCHITECTURE.md) — System architecture
- [DATABASE.md](DATABASE.md) — Migration strategy
