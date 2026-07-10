#!/usr/bin/env elixir

# Day 1 Verification Script
# Run with: mix run priv/repo/seeds/verify_day1.exs

IO.puts("\n=== Day 1 Verification ===\n")

require Ash.Query

# 1. Create Tenant with full setup → confirm Postgres schema exists
IO.puts("1. Creating Tenant with full setup...")

{:ok, %{tenant: tenant, user: owner_user, store: default_store}} =
  Algoie.Tenants.Provisioner.create_tenant_with_setup(%{
    name: "Test Tenant",
    owner_email: "owner@test.com",
    owner_name: "Owner User",
    owner_password: "password123"
  })

tenant_schema = "tenant_#{tenant.id}"

IO.puts("   ✓ Tenant created: #{tenant.id}")
IO.puts("   ✓ Owner user created: #{owner_user.id}")
IO.puts("   ✓ Default store created: #{default_store.slug}")

# Verify schema exists
schema_name = "tenant_#{tenant.id}"

{:ok, result} =
  Ecto.Adapters.SQL.query(
    Algoie.Repo,
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{schema_name}'",
    []
  )

if length(result.rows) > 0 do
  IO.puts("   ✓ Schema #{schema_name} exists")
else
  IO.puts("   ✗ Schema #{schema_name} NOT found!")
  System.halt(1)
end

# Verify StoreRegistry entry was created for default store
case Algoie.Stores.lookup_store_by_slug(default_store.slug) do
  {:ok, %{tenant_id: found_tenant_id}} ->
    if found_tenant_id == tenant.id do
      IO.puts("   ✓ StoreRegistry entry created for default store")
    else
      IO.puts("   ✗ StoreRegistry entry has wrong tenant_id!")
      System.halt(1)
    end

  _ ->
    IO.puts("   ✗ StoreRegistry entry missing for default store!")
    System.halt(1)
end

# Verify owner membership was created
case Ash.read(Algoie.Accounts.StoreStaff, actor: :system, tenant: tenant_schema) do
  {:ok, [%{role: :owner, user_id: found_user_id, store_id: found_store_id}]} ->
    if found_user_id == owner_user.id and found_store_id == default_store.id do
      IO.puts("   ✓ Owner membership created")
    else
      IO.puts("   ✗ Owner membership has wrong user/store!")
      System.halt(1)
    end

  _ ->
    IO.puts("   ✗ Owner membership missing!")
    System.halt(1)
end

# 2. Create a second Store under that Tenant
IO.puts("\n2. Creating second Store...")

{:ok, store2} =
  Ash.create(Algoie.Stores.Store, %{
    name: "Store 2",
    slug: "store-two"
  }, actor: :system, tenant: tenant_schema)

IO.puts("   ✓ Store 2 created: #{store2.slug}")

# 3. Create User B as :staff of Store 2 only
IO.puts("\n3. Creating User B with staff access to Store 2...")

{:ok, user_b} =
  Ash.create(Algoie.Accounts.User, %{
    email: "userB@test.com",
    name: "User B",
    password: "password123"
  }, action: :register_with_password, actor: :system, tenant: tenant_schema)

IO.puts("   ✓ User B created: #{user_b.id}")

# Assign User B as staff of Store 2
{:ok, _staff} =
  Ash.create(Algoie.Accounts.StoreStaff, %{
    user_id: user_b.id,
    store_id: store2.id,
    role: :staff
  }, actor: :system, tenant: tenant_schema)

IO.puts("   ✓ User B assigned as :staff of Store 2")

# 4. Attempt (as User B) to read/write default_store data → must be denied
IO.puts("\n4. Testing cross-store access denial (User B → default store)...")

case Algoie.Stores.Store
     |> Ash.Query.filter(id == ^default_store.id)
     |> Ash.read(actor: user_b, tenant: tenant_schema) do
  {:error, _} ->
    IO.puts("   ✓ User B correctly denied access to default store")

  {:ok, []} ->
    IO.puts("   ✓ User B correctly sees no default store data (filtered by policy)")

  {:ok, _} ->
    IO.puts("   ✗ User B should NOT have access to default store!")
    System.halt(1)
end

# 5. Attempt (as User B) to perform owner-only action on Store 2 → must be denied
IO.puts("\n5. Testing owner-only action denial (User B on Store 2)...")

case Ash.destroy(store2, actor: user_b, tenant: tenant_schema, context: %{store_id: store2.id, tenant: tenant_schema}) do
  {:error, _} ->
    IO.puts("   ✓ User B correctly denied owner-only action on Store 2")

  {:ok, _} ->
    IO.puts("   ✗ User B should NOT be able to delete Store 2!")
    System.halt(1)
end

# 6. Attempt the same actions with correct permissions → must succeed
IO.puts("\n6. Testing correct permissions...")

# Owner needs store_id and tenant in context for policy checks
case Ash.read(Algoie.Stores.Store,
       actor: owner_user,
       tenant: tenant_schema,
       context: %{store_id: default_store.id, tenant: tenant_schema}
     ) do
  {:ok, _} ->
    IO.puts("   ✓ Owner can read stores in tenant")

  {:error, _} ->
    IO.puts("   ✗ Owner should be able to read stores!")
    System.halt(1)
end

# Owner can destroy default store (has :owner membership)
# cascade_destroy handles StoreStaff deletion before Store
case Ash.destroy(default_store, actor: owner_user, tenant: tenant_schema, context: %{store_id: default_store.id, tenant: tenant_schema}) do
  {:ok, _} ->
    IO.puts("   ✓ Owner can delete default store (with cascade)")

  {:error, _} ->
    IO.puts("   ✗ Owner should be able to delete default store!")
    System.halt(1)
end

# 7. Subdomain routing test (simulated via StoreRegistry)
IO.puts("\n7. Subdomain routing test...")

case Algoie.Stores.lookup_store_by_slug(store2.slug) do
  {:ok, %{tenant_id: found_tenant_id, store_id: found_store_id}} ->
    if found_tenant_id == tenant.id do
      IO.puts("   ✓ StoreRegistry lookup resolves to correct tenant")
    else
      IO.puts("   ✗ StoreRegistry lookup resolved to wrong tenant!")
      System.halt(1)
    end

  {:error, :not_found} ->
    IO.puts("   ✗ StoreRegistry lookup failed!")
    System.halt(1)
end

IO.puts("\n=== All Day 1 verifications passed! ===\n")
