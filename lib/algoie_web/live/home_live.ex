defmodule AlgoieWeb.HomeLive do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Algoie")}
  end
end
