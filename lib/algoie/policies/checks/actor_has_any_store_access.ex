defmodule Algoie.Policies.Checks.ActorHasAnyStoreAccess do
  @moduledoc """
  Policy check that verifies the actor has at least one StoreStaff membership
  in the current tenant. Used for read operations that list all stores in a tenant.
  Uses raw SQL to avoid circular authorization.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor has any store access in the tenant"

  @impl true
  def match?(actor, authorizer, _opts) do
    tenant_id = authorizer.context[:tenant]

    case tenant_id do
      nil ->
        {:ok, false}

      tenant_id when is_binary(tenant_id) ->
        user_id = Ecto.UUID.cast!(actor.id)

        case Ecto.Adapters.SQL.query(
               Algoie.Repo,
               "SELECT 1 FROM \"#{tenant_id}\".store_staff WHERE user_id = '#{user_id}' LIMIT 1",
               []
             ) do
          {:ok, %{rows: [_ | _]}} ->
            {:ok, true}

          _ ->
            {:ok, false}
        end

      _ ->
        {:ok, false}
    end
  end
end
