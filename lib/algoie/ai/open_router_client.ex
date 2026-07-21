defmodule Algoie.AI.OpenRouterClient do
  @moduledoc "OpenRouter adapter. This is the only module that sends AI traffic outside Algoie."

  @behaviour Algoie.AI.ModelClient

  alias Algoie.PlatformAISettings

  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  @impl true
  def chat(messages, opts \\ []) when is_list(messages) do
    settings = Keyword.get(opts, :settings, PlatformAISettings.get())
    model = Keyword.get(opts, :model, settings.default_model)
    tools = Keyword.get(opts, :tools, [])

    with true <- PlatformAISettings.configured?(settings),
         true <- PlatformAISettings.allowed_model?(settings, model),
         key when is_binary(key) <- PlatformAISettings.openrouter_api_key(settings),
         {:ok, response} <- request(key, model, messages, tools, opts) do
      {:ok, response}
    else
      false -> {:error, :not_configured_or_model_not_allowed}
      nil -> {:error, :not_configured_or_model_not_allowed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(key, model, messages, tools, opts) do
    body =
      %{model: model, messages: messages, temperature: 0.2, max_tokens: 800}
      |> then(fn body ->
        if tools != [], do: Map.put(body, :tools, tools), else: body
      end)

    tool_names = if tools != [], do: Enum.map(tools, & &1.function.name), else: []
    require Logger
    Logger.debug("OpenRouter request: model=#{model} tools=#{inspect(tool_names)}")

    case Req.post(@endpoint,
           json: body,
           headers: [
             {"authorization", "Bearer #{key}"},
             {"http-referer", AlgoieWeb.PublicURL.origin()}
           ],
           receive_timeout: Keyword.get(opts, :receive_timeout, 30_000)
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:provider_error, status}}
      {:error, reason} -> {:error, {:network_error, reason}}
    end
  end
end
