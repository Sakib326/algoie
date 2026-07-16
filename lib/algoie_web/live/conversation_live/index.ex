defmodule AlgoieWeb.ConversationLive.Index do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Conversations") |> assign(:active, :conversations)}
  end
end
