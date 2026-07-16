defmodule AlgoieWeb.Scope do
  @moduledoc """
  Builds the standard Ash options for dashboard requests.

  Every tenant-scoped resource is protected by `ActorHasStoreAccess`, which reads
  `store_id` and `tenant` from the Ash context. This helper packages the tenant,
  actor, and that context so authorized reads/writes resolve to the current store.
  """

  @doc """
  Returns `[tenant:, actor:, context:]` for the current dashboard socket,
  merged with any `extra` options (e.g. `load:`).
  """
  def opts(socket, extra \\ []) do
    Keyword.merge(
      [
        tenant: socket.assigns.tenant,
        actor: socket.assigns[:current_user],
        context: %{store_id: socket.assigns.store_id, tenant: socket.assigns.tenant}
      ],
      extra
    )
  end
end
