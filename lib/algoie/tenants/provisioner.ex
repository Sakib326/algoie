defmodule Algoie.Tenants.Provisioner do
  @moduledoc """
  Handles transactional provisioning of tenant schemas.
  Creates Tenant, schema, default Store, owner User, and owner StoreStaff membership.
  If any step fails, rolls back everything including dropping any created schema.
  """

  alias Algoie.Repo
  alias Algoie.Accounts.{StoreStaff, Tenant, TenantMembership, User}
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
    case Ash.create(
           Tenant,
           %{
             name: attrs.name,
             slug: Map.get(attrs, :tenant_slug) || generate_tenant_slug(attrs.name),
             owner_email: attrs.owner_email
           },
           actor: :system
         ) do
      {:ok, tenant} ->
        schema_name = "tenant_#{tenant.id}"

        case Repo.create_tenant_schema(schema_name) do
          :ok ->
            case run_tenant_migrations(schema_name) do
              :ok ->
                with {:ok, store} <-
                       Ash.create(
                         Store,
                         %{
                           name: attrs.name,
                           slug: generate_slug(attrs.name)
                         },
                         actor: :system,
                         tenant: schema_name
                       ),
                     {:ok, user} <-
                       Ash.create(
                         User,
                         %{
                           email: attrs.owner_email,
                           name: attrs.owner_name,
                           password: attrs.owner_password
                         },
                         action: :register_with_password,
                         actor: :system
                       ),
                     {:ok, _tenant_membership} <-
                       Ash.create(
                         TenantMembership,
                         %{tenant_id: tenant.id, user_id: user.id, role: :owner},
                         actor: :system
                       ),
                     {:ok, _staff} <-
                       Ash.create(
                         StoreStaff,
                         %{
                           user_id: user.id,
                           store_id: store.id,
                           role: :owner
                         },
                         actor: :system,
                         tenant: schema_name
                       ),
                     {:ok, _updated_user} <-
                       Ash.update(user, %{default_tenant: schema_name}, actor: :system) do
                  {:ok, %{tenant: tenant, user: user, store: store}}
                else
                  {:error, changeset} ->
                    rollback_tenant(tenant, schema_name)
                    {:error, changeset}
                end

              {:error, reason} ->
                rollback_tenant(tenant, schema_name)
                {:error, reason}
            end

          {:error, reason} ->
            rollback_tenant(tenant, schema_name)
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, changeset}
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

  # Fully undo a partially-provisioned tenant so no orphaned rows remain in the
  # public schema. Removes registry entries (created by Store's after_action),
  # drops the tenant schema, and deletes the Tenant record.
  defp rollback_tenant(tenant, schema_name) do
    Ecto.Adapters.SQL.query(
      Repo,
      "DELETE FROM public.store_registry WHERE tenant_id = $1",
      [tenant.id]
    )

    drop_tenant_schema(schema_name)

    Ash.destroy(tenant, actor: :system)
    :ok
  end

  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(&"#{&1}-#{System.unique_integer([:positive])}")
  end

  defp generate_tenant_slug(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> case do
        "" -> "tenant"
        value -> value
      end

    "#{base}-#{System.unique_integer([:positive])}"
  end
end
