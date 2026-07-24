defmodule Algoie.ChannelStudioTestProvider do
  @behaviour Algoie.ChannelStudio.Provider

  @impl true
  def request(method, path, body, params, headers) do
    send(Application.fetch_env!(:algoie, :channel_studio_test_pid), {
      :channel_studio_request,
      method,
      path,
      body,
      params,
      headers
    })

    {:ok, %{"success" => true}}
  end
end
