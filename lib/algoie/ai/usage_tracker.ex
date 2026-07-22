defmodule Algoie.AI.UsageTracker do
  @moduledoc "Tracks per-request token usage and enforces budget limits."

  import Ecto.Query
  alias Algoie.Repo

  @table "platform_ai_usage"

  @model_costs %{
    "deepseek/deepseek-v4-flash" => %{input: 0.01, output: 0.03},
    "google/gemini-2.5-flash" => %{input: 0.015, output: 0.06},
    "openai/gpt-4o-mini" => %{input: 0.15, output: 0.60}
  }

  def record(model, usage, context \\ %{}) do
    prompt = Map.get(usage, :prompt_tokens, 0) || Map.get(usage, "prompt_tokens", 0)
    completion = Map.get(usage, :completion_tokens, 0) || Map.get(usage, "completion_tokens", 0)

    cost = calculate_cost(model, prompt, completion)

    user_id =
      case Map.get(context, :actor) do
        %{id: id} -> id
        _ -> nil
      end

    Repo.insert_all(@table, [
      %{
        id: dump_uuid(Ecto.UUID.generate()),
        model: model,
        tokens_prompt: prompt,
        tokens_completion: completion,
        cost_cents: cost,
        store_id: dump_uuid(Map.get(context, :store_id)),
        user_id: dump_uuid(user_id),
        inserted_at: DateTime.utc_now()
      }
    ])

    {:ok, cost}
  end

  def monthly_cost_cents do
    start_of_month =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> Map.put(:day, 1)
      |> Map.put(:hour, 0)
      |> Map.put(:minute, 0)
      |> Map.put(:second, 0)

    query = from(u in @table, where: u.inserted_at >= ^start_of_month, select: sum(u.cost_cents))

    Repo.one(query) || 0
  end

  def check_budget!(settings) do
    monthly = monthly_cost_cents()
    budget = settings.monthly_budget_cents

    if budget && monthly >= budget do
      {:error, :monthly_budget_exceeded}
    else
      :ok
    end
  end

  defp calculate_cost(model, prompt_tokens, completion_tokens) do
    costs = Map.get(@model_costs, model, %{input: 0.02, output: 0.06})
    input_cost = Float.round(costs.input * prompt_tokens / 1000, 4)
    output_cost = Float.round(costs.output * completion_tokens / 1000, 4)
    total = Float.round(input_cost + output_cost, 4)
    round(total * 100)
  end

  defp dump_uuid(nil), do: nil
  defp dump_uuid(id) when is_binary(id), do: Ecto.UUID.dump!(id)
end
