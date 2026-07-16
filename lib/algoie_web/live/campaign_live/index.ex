defmodule AlgoieWeb.CampaignLive.Index do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Ad Campaigns") |> assign(:active, :campaigns)}
  end
end
