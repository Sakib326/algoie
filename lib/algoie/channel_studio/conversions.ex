defmodule Algoie.ChannelStudio.Conversions do
  @moduledoc "Meta Pixel and server-side conversion operations."

  alias Algoie.ChannelStudio

  def destinations(account_id) do
    ChannelStudio.get("/accounts/#{ChannelStudio.segment(account_id)}/conversion-destinations")
  end

  def destination(account_id, destination_id) do
    ChannelStudio.get(destination_path(account_id, destination_id))
  end

  def metrics(account_id, destination_id, params \\ []) do
    ChannelStudio.get(destination_path(account_id, destination_id) <> "/metrics", params)
  end

  def associations(account_id, destination_id) do
    ChannelStudio.get(destination_path(account_id, destination_id) <> "/associations")
  end

  def pixels(account_id, params \\ []) do
    ChannelStudio.get("/accounts/#{ChannelStudio.segment(account_id)}/tracking-tags", params)
  end

  # Pixel creation is intentionally a direct, one-shot operation. Callers must
  # disable resubmission and must never auto-retry it because the API is not idempotent.
  def create_pixel(account_id, payload) do
    ChannelStudio.mutate(
      :post,
      "/accounts/#{ChannelStudio.segment(account_id)}/tracking-tags",
      payload
    )
  end

  def pixel(account_id, pixel_id) do
    ChannelStudio.get(tracking_path(account_id, pixel_id))
  end

  def update_pixel(account_id, pixel_id, payload) do
    ChannelStudio.mutate(:patch, tracking_path(account_id, pixel_id), payload)
  end

  def pixel_stats(account_id, pixel_id, params \\ []) do
    ChannelStudio.get(tracking_path(account_id, pixel_id) <> "/stats", params)
  end

  def quality(account_id, destination_id) do
    ChannelStudio.get("/ads/conversions/quality",
      accountId: account_id,
      destinationId: destination_id
    )
  end

  def send_events(payload), do: ChannelStudio.mutate(:post, "/ads/conversions", payload)

  defp destination_path(account_id, destination_id) do
    "/accounts/#{ChannelStudio.segment(account_id)}/conversion-destinations/#{ChannelStudio.segment(destination_id)}"
  end

  defp tracking_path(account_id, pixel_id) do
    "/accounts/#{ChannelStudio.segment(account_id)}/tracking-tags/#{ChannelStudio.segment(pixel_id)}"
  end
end
