defmodule Algoie.Accounts.UserContext do
  @moduledoc """
  Helper to load the current user's store context from their StoreStaff membership.
  """

  alias Algoie.Accounts.StoreStaff
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
                 SELECT ss.store_id, s.name, ss.role
                 FROM "#{schema}".store_staff ss
                 JOIN "#{schema}".stores s ON s.id = ss.store_id
                 WHERE ss.user_id = $1
                 """,
                 [user_id]
               ) do
            {:ok, %{rows: rows}} ->
              Enum.map(rows, fn [store_id, store_name, role] ->
                %{store_id: store_id, store_name: store_name, tenant: schema, role: role}
              end)

            _ ->
              []
          end
        end)
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
                 "SELECT 1 FROM \"#{schema}\".store_staff WHERE user_id = $1 LIMIT 1",
                 [user_id]
               ) do
            {:ok, %{rows: [_ | _]}} -> true
            _ -> false
          end
        end)
    end
  end

  defp get_all_tenants do
    case Algoie.Repo.all(from(t in "tenants", prefix: "public", select: t.id)) do
      ids when is_list(ids) -> ids
      _ -> []
    end
  end
end
