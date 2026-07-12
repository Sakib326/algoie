defmodule AlgoieWeb.StorefrontHomeLive do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Store")}
  end
end
