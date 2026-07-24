defmodule Algoie.ChannelStudio.MetaAds do
  @moduledoc "Paid-media operations. Organic publishing must not call this module."

  alias Algoie.ChannelStudio

  def connect(profile_id, parent_account_id, platform, redirect_url)
      when platform in ~w(facebook instagram) do
    ChannelStudio.get("/connect/#{platform}/ads",
      profileId: profile_id,
      accountId: parent_account_id,
      headless: true,
      redirect_url: redirect_url
    )
  end

  def accounts(account_id), do: ChannelStudio.get("/ads/accounts", accountId: account_id)
  def ads(params), do: ChannelStudio.get("/ads", params)
  def campaigns(params), do: ChannelStudio.get("/ads/campaigns", params)
  def tree(params), do: ChannelStudio.get("/ads/tree", params)
  def timeline(params), do: ChannelStudio.get("/ads/timeline", params)
  def boost(payload), do: ChannelStudio.mutate(:post, "/ads/boost", payload)
  def create(payload), do: ChannelStudio.mutate(:post, "/ads/create", payload)

  def update_campaign(id, payload) do
    ChannelStudio.mutate(:patch, "/ads/campaigns/#{ChannelStudio.segment(id)}", payload)
  end

  def update_ad_set(id, payload) do
    ChannelStudio.mutate(:patch, "/ads/ad-sets/#{ChannelStudio.segment(id)}", payload)
  end

  def update_ad(id, payload) do
    ChannelStudio.mutate(:patch, "/ads/#{ChannelStudio.segment(id)}", payload)
  end

  def targeting_search(params), do: ChannelStudio.get("/ads/targeting/search", params)
  def audiences(params), do: ChannelStudio.get("/ads/audiences", params)
  def lead_forms(params), do: ChannelStudio.get("/ads/lead-forms", params)
  def leads(params), do: ChannelStudio.get("/ads/leads", params)
end
