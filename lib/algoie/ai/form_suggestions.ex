defmodule Algoie.AI.FormSuggestions do
  @moduledoc "Generates structured, non-destructive suggestions for catalog edit forms."

  alias Algoie.AI.{OpenRouterClient, UsageTracker}
  alias Algoie.PlatformAISettings

  @fields %{
    "product" => ~w(name slug description meta_title meta_description sku),
    "category" => ~w(name slug description meta_title meta_description),
    "brand" => ~w(name slug description meta_title meta_description)
  }

  def suggest(resource, values, context) when is_map(values) do
    settings = PlatformAISettings.get()

    with :ok <- UsageTracker.check_budget!(settings),
         true <- PlatformAISettings.configured?(settings),
         fields when is_list(fields) <- Map.get(@fields, resource),
         {:ok, response} <-
           OpenRouterClient.chat(messages(resource, values, fields),
             settings: settings,
             max_tokens: 1_200,
             temperature: 0.3,
             response_format: %{type: "json_object"}
           ),
         :ok <- track_usage(response, context),
         {:ok, suggestions} <- decode_response(response) do
      {:ok, sanitize(suggestions, fields)}
    else
      false -> {:error, :not_configured}
      nil -> {:error, :unsupported_resource}
      {:error, reason} -> {:error, reason}
    end
  end

  defp messages(resource, values, fields) do
    current = Map.take(values, fields)

    [
      %{
        role: "system",
        content: """
        You improve ecommerce catalog copy. Return ONLY one valid JSON object with these keys:
        #{Enum.join(fields, ", ")}.
        Every value must be a string. Preserve factual meaning and do not invent specifications,
        claims, prices, or certifications. Slugs must contain only lowercase letters, numbers, and
        single hyphens. meta_title must be at most 60 characters and meta_description at most 160.
        Make descriptions concise, polished, shopper-friendly, and search-aware.
        """
      },
      %{
        role: "user",
        content: "Improve this #{resource} edit form:\n#{Jason.encode!(current)}"
      }
    ]
  end

  defp decode_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    content = String.trim(content || "")

    case Jason.decode(content) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> decode_embedded_json(content)
    end
  end

  defp decode_response(_response), do: {:error, :invalid_provider_response}

  defp decode_embedded_json(content) do
    case Regex.run(~r/\{.*\}/s, content) do
      [json] ->
        case Jason.decode(json) do
          {:ok, map} when is_map(map) -> {:ok, map}
          _ -> {:error, :invalid_suggestions}
        end

      _ ->
        {:error, :invalid_suggestions}
    end
  end

  defp sanitize(suggestions, fields) do
    fields
    |> Enum.reduce(%{}, fn field, acc ->
      case Map.get(suggestions, field) do
        value when is_binary(value) and value != "" -> Map.put(acc, field, limit(field, value))
        _ -> acc
      end
    end)
  end

  defp limit("meta_title", value), do: String.slice(value, 0, 60)
  defp limit("meta_description", value), do: String.slice(value, 0, 160)
  defp limit("slug", value), do: slugify(value)
  defp limit(_field, value), do: String.trim(value)

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp track_usage(%{"model" => model, "usage" => usage}, context) do
    UsageTracker.record(model, usage, context)
    :ok
  end

  defp track_usage(_response, _context), do: :ok
end
