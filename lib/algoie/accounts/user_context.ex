defmodule Algoie.Accounts.UserContext do
  @moduledoc """
  Helper to load the current user's store context from their StoreStaff membership.
  """

  alias Algoie.Accounts.{StorePermissions, StoreStaff}
  alias Algoie.Repo
  import Ecto.Query

  @doc """
  Load the user's first store context (tenant and store_id).
  Returns {:ok, %{tenant: String.t(), store_id: String.t()}} or {:error, :no_store}.
  """
  def load_store_context(user) do
    case Ash.read(StoreStaff,
           query: [filter: [user_id: user.id]],
           authorize?: false
         ) do
      {:ok, [staff | _]} ->
        store_id = staff.store_id

        tenant =
          case staff do
            %{__metadata__: %{tenant: tenant}} -> tenant
            _ -> nil
          end

        if tenant do
          {:ok, %{tenant: tenant, store_id: store_id}}
        else
          {:error, :no_tenant}
        end

      _ ->
        {:error, :no_store}
    end
  end

  @doc """
  Load ALL stores the user has access to across all tenants.
  Returns a list of %{store_id, store_name, tenant, role} maps.
  """
  def load_all_user_stores(user_id) do
    case get_all_tenants() do
      [] ->
        []

      tenants ->
        Enum.flat_map(tenants, fn tenant_id ->
          schema = "tenant_#{tenant_id}"

          case Ecto.Adapters.SQL.query(
                 Algoie.Repo,
                 """
                 SELECT ss.store_id::text, s.name, ss.role, ss.permissions
                 FROM "#{schema}".store_staff ss
                 JOIN "#{schema}".stores s ON s.id = ss.store_id
                 WHERE ss.user_id::text = $1
                 """,
                 [user_id]
               ) do
            {:ok, %{rows: rows}} ->
              Enum.map(rows, fn [store_id, store_name, role, permissions] ->
                membership_map(store_id, store_name, schema, role, permissions)
              end)

            _ ->
              []
          end
        end)
    end
  end

  @doc "Loads one current membership from the database instead of trusting session state."
  def find_store_access(user_id, store_id) do
    user_id
    |> load_all_user_stores()
    |> Enum.find(&(&1.store_id == to_string(store_id)))
    |> case do
      nil -> {:error, :not_a_member}
      store -> {:ok, store}
    end
  end

  @doc "Returns tenants in which the user owns at least one store."
  def load_owner_tenants(user_id) do
    owner_tenants =
      user_id
      |> load_all_user_stores()
      |> Enum.filter(&(&1.role == :owner))
      |> Map.new(&{String.replace_leading(&1.tenant, "tenant_", ""), &1.tenant})

    if map_size(owner_tenants) == 0 do
      []
    else
      Repo.query!(
        "SELECT id::text, name FROM public.tenants WHERE id::text = ANY($1::text[]) ORDER BY name",
        [Map.keys(owner_tenants)]
      ).rows
      |> Enum.map(fn [id, name] -> %{id: id, tenant: owner_tenants[id], name: name} end)
    end
  end

  @doc """
  Get the list of tenant IDs the user has access to.
  """
  def get_user_tenants(user_id) do
    case get_all_tenants() do
      [] ->
        []

      tenants ->
        Enum.filter(tenants, fn tenant_id ->
          schema = "tenant_#{tenant_id}"

          case Ecto.Adapters.SQL.query(
                 Algoie.Repo,
                 "SELECT 1 FROM \"#{schema}\".store_staff WHERE user_id::text = $1 LIMIT 1",
                 [user_id]
               ) do
            {:ok, %{rows: [_ | _]}} -> true
            _ -> false
          end
        end)
    end
  end

  defp get_all_tenants do
    case Algoie.Repo.all(
           from(t in "tenants", prefix: "public", select: fragment("?::text", t.id))
         ) do
      ids when is_list(ids) -> ids
      _ -> []
    end
  end

  defp membership_map(store_id, store_name, tenant, role, permissions) do
    role = String.to_existing_atom(role)

    %{
      store_id: store_id,
      store_name: store_name,
      tenant: tenant,
      role: role,
      permissions: StorePermissions.effective(role, permissions)
    }
  end
end
