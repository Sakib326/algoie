defmodule AlgoieWeb.Live.OnStoreMount do
  @moduledoc """
  OnMount hook that reads tenant and store_id from the Plug session
  (set by StoreSlugPlug) and makes them available as socket assigns.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    tenant = session["store_tenant"]
    store_id = session["store_id"]

    {:cont, socket |> assign(:tenant, tenant) |> assign(:store_id, store_id)}
  end
end
