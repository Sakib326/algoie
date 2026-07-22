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

  @impl true
  def chat_stream(messages, opts \\ []) when is_list(messages) do
    settings = Keyword.get(opts, :settings, PlatformAISettings.get())
    model = Keyword.get(opts, :model, settings.default_model)
    tools = Keyword.get(opts, :tools, [])

    with true <- PlatformAISettings.configured?(settings),
         true <- PlatformAISettings.allowed_model?(settings, model),
         key when is_binary(key) <- PlatformAISettings.openrouter_api_key(settings),
         {:ok, response} <- stream_request(key, model, messages, tools, opts) do
      {:ok, response}
    else
      false -> {:error, :not_configured_or_model_not_allowed}
      nil -> {:error, :not_configured_or_model_not_allowed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(key, model, messages, tools, opts) do
    body =
      %{
        model: model,
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0.2),
        max_tokens: Keyword.get(opts, :max_tokens, 800)
      }
      |> maybe_put_response_format(opts)
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

  defp stream_request(key, model, messages, tools, opts) do
    body =
      %{
        model: model,
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0.2),
        max_tokens: Keyword.get(opts, :max_tokens, 800),
        stream: true
      }
      |> Map.put(:stream_options, %{include_usage: true})
      |> then(fn body -> if tools != [], do: Map.put(body, :tools, tools), else: body end)

    on_delta = Keyword.get(opts, :on_delta, fn _delta -> :ok end)
    state_key = {__MODULE__, make_ref()}
    Process.put(state_key, %{buffer: "", content: "", tool_calls: %{}, model: model, usage: %{}})

    result =
      Req.post(@endpoint,
        json: body,
        headers: [
          {"authorization", "Bearer #{key}"},
          {"http-referer", AlgoieWeb.PublicURL.origin()},
          {"accept", "text/event-stream"}
        ],
        receive_timeout: Keyword.get(opts, :receive_timeout, 30_000),
        into: fn {:data, data}, {request, response} ->
          state = Process.get(state_key)
          Process.put(state_key, consume_sse(state, data, on_delta))
          {:cont, {request, response}}
        end
      )

    state = Process.delete(state_key)

    case result do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, assembled_response(state)}
      {:ok, %{status: status}} -> {:error, {:provider_error, status}}
      {:error, reason} -> {:error, {:network_error, reason}}
    end
  end

  defp consume_sse(state, data, on_delta) do
    normalized = String.replace(state.buffer <> data, "\r\n", "\n")
    parts = String.split(normalized, "\n\n")
    {events, [buffer]} = Enum.split(parts, -1)

    state = %{state | buffer: buffer}
    Enum.reduce(events, state, &consume_event(&2, &1, on_delta))
  end

  defp consume_event(state, event, on_delta) do
    payload =
      event
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", &(&1 |> String.replace_prefix("data:", "") |> String.trim_leading()))

    case payload do
      "" ->
        state

      "[DONE]" ->
        state

      json ->
        case Jason.decode(json) do
          {:ok, chunk} -> merge_chunk(state, chunk, on_delta)
          {:error, _reason} -> state
        end
    end
  end

  defp merge_chunk(state, chunk, on_delta) do
    delta = get_in(chunk, ["choices", Access.at(0), "delta"]) || %{}
    content = delta["content"] || ""

    if content != "", do: on_delta.(content)

    tool_calls =
      Enum.reduce(delta["tool_calls"] || [], state.tool_calls, fn call, calls ->
        index = call["index"] || 0
        existing = Map.get(calls, index, %{"function" => %{"name" => "", "arguments" => ""}})

        updated =
          existing
          |> maybe_put("id", call["id"])
          |> maybe_put("type", call["type"])
          |> update_in(
            ["function", "name"],
            &(&1 <> (get_in(call, ["function", "name"]) || ""))
          )
          |> update_in(
            ["function", "arguments"],
            &(&1 <> (get_in(call, ["function", "arguments"]) || ""))
          )

        Map.put(calls, index, updated)
      end)

    %{
      state
      | content: state.content <> content,
        tool_calls: tool_calls,
        model: chunk["model"] || state.model,
        usage: chunk["usage"] || state.usage
    }
  end

  defp assembled_response(state) do
    message =
      %{"role" => "assistant", "content" => state.content}
      |> then(fn message ->
        if map_size(state.tool_calls) > 0 do
          Map.put(
            message,
            "tool_calls",
            state.tool_calls |> Enum.sort() |> Enum.map(&elem(&1, 1))
          )
        else
          message
        end
      end)

    %{
      "model" => state.model,
      "usage" => state.usage,
      "choices" => [%{"message" => message}]
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_response_format(body, opts) do
    case Keyword.get(opts, :response_format) do
      nil -> body
      format -> Map.put(body, :response_format, format)
    end
  end
end
