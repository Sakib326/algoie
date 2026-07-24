defmodule Algoie.ChannelStudio.Content do
  @moduledoc "Provider-neutral organic post operations."

  alias Algoie.ChannelStudio

  @organic_platforms ~w(facebook instagram tiktok)

  def organic_platforms, do: @organic_platforms

  def list(params \\ []), do: ChannelStudio.get("/posts", params)
  def get(id), do: ChannelStudio.get("/posts/#{ChannelStudio.segment(id)}")
  def create(payload), do: ChannelStudio.mutate(:post, "/posts", payload)
  def retry(id), do: ChannelStudio.mutate(:post, "/posts/#{ChannelStudio.segment(id)}/retry")
  def delete(id), do: ChannelStudio.mutate(:delete, "/posts/#{ChannelStudio.segment(id)}", nil)

  def unpublish(id, platform) when platform in @organic_platforms do
    ChannelStudio.mutate(:post, "/posts/#{ChannelStudio.segment(id)}/unpublish", %{
      "platform" => platform
    })
  end
end
