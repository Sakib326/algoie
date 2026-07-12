defmodule Algoie.Accounts.UserContext do
  @moduledoc """
  Helper to load the current user's store context from their StoreStaff membership.
  """

  alias Algoie.Accounts.StoreStaff
  require Ash.Query

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

        # Get the tenant from the staff record's metadata
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
end
