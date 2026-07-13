defmodule AlgoieWeb.CampaignLive.Index do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Ad Campaigns")}
  end
end
