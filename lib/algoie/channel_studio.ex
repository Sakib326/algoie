defmodule Algoie.ChannelStudio do
  @moduledoc "Provider-neutral entry point for social, messaging, ads and conversion operations."

  @default_provider Algoie.SocialPublishing.Adapters.Zernio

  def provider do
    Application.get_env(:algoie, :channel_studio_provider, @default_provider)
  end

  def request(method, path, body \\ nil, params \\ [], headers \\ []) do
    provider().request(method, path, body, compact(params), headers)
  end

  def get(path, params \\ []), do: request(:get, path, nil, params)

  def mutate(method, path, body \\ %{}) do
    request(method, path, body, [], [{"x-request-id", Ecto.UUID.generate()}])
  end

  def segment(value), do: value |> to_string() |> URI.encode_www_form()

  defp compact(params), do: Enum.reject(params, fn {_key, value} -> value in [nil, ""] end)
end
