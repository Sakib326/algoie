defmodule Algoie.Policies.Checks.ActorHasStoreAccess do
  @moduledoc """
  Policy check that verifies the actor has the required access level for a store.

  Looks up the StoreStaff row for (actor.id, store_id) and compares role.
  Uses raw SQL to avoid circular authorization.

  The routing plug must set both:
  - context[:tenant] — the Tenant ID (for schema routing)
  - context[:store_id] — the Store ID (for this policy check)
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor has #{Keyword.get(opts, :level, :staff)} access to the store"

  @impl true
  def match?(actor, authorizer, opts) do
    required_level = Keyword.get(opts, :level, :staff)

    store_id = authorizer.context[:store_id]
    tenant_id = authorizer.context[:tenant]

    case {store_id, tenant_id} do
      {nil, _} ->
        {:ok, false}

      {_, nil} ->
        {:ok, false}

      {store_id, tenant_id} ->
        case get_store_staff_role(actor, store_id, tenant_id) do
          nil ->
            {:ok, false}

          :owner ->
            {:ok, true}

          :staff when required_level == :owner ->
            {:ok, false}

          :staff when required_level == :staff ->
            {:ok, true}
        end
    end
  end

  defp get_store_staff_role(nil, _store_id, _tenant_id), do: nil

  defp get_store_staff_role(actor, store_id, tenant_id) do
    case Ecto.Adapters.SQL.query(
           Algoie.Repo,
           "SELECT role FROM #{tenant_id}.store_staff WHERE user_id = $1 AND store_id = $2",
           [actor.id, store_id]
         ) do
      {:ok, %{rows: [[role]]}} -> String.to_existing_atom(role)
      _ -> nil
    end
  end
end
