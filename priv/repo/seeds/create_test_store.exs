#!/usr/bin/env mix

import Config

# Run with: mix run priv/repo/seeds/create_test_store.exs

{:ok, _} = Application.ensure_all_started(:algoie)

alias Algoie.Repo

{:ok, %{tenant: tenant, user: user, store: store}} =
  Algoie.Tenants.Provisioner.create_tenant_with_setup(%{
    name: "Verify Store",
    owner_email: "verify@example.com",
    owner_name: "Verify Admin",
    owner_password: "password123"
  })

schema_name = "tenant_#{tenant.id}"

# Update store slug
store_tenant = "tenant_#{tenant.id |> String.replace_leading("tenant_", "")}"

{:ok, updated_store} =
  Ash.update(store, %{slug: "verify-store-1314"},
    action: :update,
    actor: :system,
    tenant: store_tenant
  )

# Update registry entry
Repo.query!(
  "UPDATE public.store_registry SET slug = 'verify-store-1314' WHERE store_id = '#{updated_store.id}'"
)

IO.puts("""
Test store created successfully!

  Store:  #{store.name}
  Slug:   verify-store-1314
  Email:  verify@example.com
  Pass:   password123

Visit:   http://verify-store-1314.lvh.me:4000/
""")
