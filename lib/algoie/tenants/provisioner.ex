defmodule Algoie.Tenants.Provisioner do
  @moduledoc """
  Handles transactional provisioning of tenant schemas.
  Creates Tenant, schema, default Store, owner User, and owner StoreStaff membership.
  If any step fails, rolls back everything including dropping any created schema.
  """

  alias Algoie.Repo
  alias Algoie.Accounts.{Tenant, User, StoreStaff}
  alias Algoie.Stores.Store

  @doc """
  Create a tenant with its Postgres schema, default store, and owner account.

  attrs must include:
  - name: tenant name
  - owner_email: owner's email
  - owner_name: owner's display name
  - owner_password: owner's password (min 8 chars)

  Returns {:ok, %{tenant, user, store}} on success, {:error, reason} on failure.
  """
  def create_tenant_with_setup(attrs) do
    # Step 1: Create the tenant record
    {:ok, tenant} =
      Ash.create(
        Tenant,
        %{
          name: attrs.name,
          owner_email: attrs.owner_email
        }, actor: :system)

    schema_name = "tenant_#{tenant.id}"

    # Step 2: Create schema and run migrations (outside Ecto transaction)
    case Repo.create_tenant_schema(schema_name) do
      :ok ->
        case run_tenant_migrations(schema_name) do
          :ok ->
            # Step 3: Create resources in tenant schema (each in its own transaction)
            with {:ok, store} <-
                   Ash.create(
                     Store,
                     %{
                       name: "#{attrs.name} Store",
                       slug: generate_slug(attrs.name)
                     }, actor: :system, tenant: schema_name),
                 {:ok, user} <-
                   Ash.create(
                     User,
                     %{
                       email: attrs.owner_email,
                       name: attrs.owner_name,
                       password: attrs.owner_password
                     },
                     action: :register_with_password,
                     actor: :system,
                     tenant: schema_name
                   ),
                 {:ok, _staff} <-
                   Ash.create(
                     StoreStaff,
                     %{
                       user_id: user.id,
                       store_id: store.id,
                       role: :owner
                     }, actor: :system, tenant: schema_name) do
              {:ok, %{tenant: tenant, user: user, store: store}}
            else
              {:error, changeset} ->
                drop_tenant_schema(schema_name)
                {:error, changeset}
            end

          {:error, reason} ->
            drop_tenant_schema(schema_name)
            {:error, reason}
        end

      {:error, reason} ->
        drop_tenant_schema(schema_name)
        {:error, reason}
    end
  end

  defp run_tenant_migrations(schema_name) do
    path = Application.app_dir(:algoie, "priv/repo/tenant_migrations")

    try do
      Ecto.Migrator.with_repo(Repo, fn repo ->
        Ecto.Migrator.run(repo, path, :up, prefix: schema_name, all: true)
      end)

      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp drop_tenant_schema(schema_name) do
    query = "DROP SCHEMA IF EXISTS \"#{schema_name}\" CASCADE"
    Ecto.Adapters.SQL.query!(Repo, query, [])
  end

  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(&"#{&1}-#{System.unique_integer([:positive])}")
  end
end
