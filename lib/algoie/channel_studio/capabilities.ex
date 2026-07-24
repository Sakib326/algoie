defmodule Algoie.ChannelStudio.Capabilities do
  @moduledoc "Static capability contract derived from llms-full.txt."

  @capabilities %{
    facebook: %{publish: true, posts: true, messages: true, comments: true, analytics: true},
    instagram: %{publish: true, posts: true, messages: true, comments: true, analytics: true},
    whatsapp: %{publish: false, posts: false, messages: true, comments: false, analytics: false},
    tiktok: %{publish: true, posts: true, messages: false, comments: false, analytics: :limited},
    metaads: %{publish: false, posts: false, messages: false, comments: :ads, analytics: :paid}
  }

  def all, do: @capabilities
  def for_platform(platform) when is_binary(platform), do: for_existing_atom(platform)
  def for_platform(platform) when is_atom(platform), do: Map.get(@capabilities, platform, %{})

  def supports?(platform, capability),
    do: Map.get(for_platform(platform), capability, false) not in [false, nil]

  defp for_existing_atom(platform) do
    Enum.find_value(@capabilities, %{}, fn {key, value} ->
      if Atom.to_string(key) == platform, do: value
    end)
  end
end
