defmodule Algoie.ChannelStudio.Analytics do
  @moduledoc "Organic analytics operations. Paid reporting lives in MetaAds."

  alias Algoie.ChannelStudio

  def overview(params), do: ChannelStudio.get("/analytics", params)
  def daily(params), do: ChannelStudio.get("/analytics/daily-metrics", params)

  def facebook_page(account_id, params) do
    ChannelStudio.get(
      "/analytics/facebook/page-insights",
      Keyword.put(params, :accountId, account_id)
    )
  end

  def instagram_account(account_id, params) do
    ChannelStudio.get(
      "/analytics/instagram/account-insights",
      Keyword.put(params, :accountId, account_id)
    )
  end

  def instagram_followers(account_id, params) do
    ChannelStudio.get(
      "/analytics/instagram/follower-history",
      Keyword.put(params, :accountId, account_id)
    )
  end

  def instagram_demographics(account_id, params \\ []) do
    ChannelStudio.get(
      "/analytics/instagram/demographics",
      Keyword.put(params, :accountId, account_id)
    )
  end

  def tiktok_account(account_id, params) do
    ChannelStudio.get(
      "/analytics/tiktok/account-insights",
      Keyword.put(params, :accountId, account_id)
    )
  end
end
