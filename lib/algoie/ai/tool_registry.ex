defmodule Algoie.AI.ToolRegistry do
  @moduledoc "Validated allow-list of AI tools configured by application code."

  @risk_levels [:read_only, :draft, :write, :external_effect, :destructive_or_financial]

  def tools do
    Application.get_env(:algoie, :ai_tools, [])
    |> Enum.map(& &1.definition())
    |> Enum.map(&validate!/1)
  end

  def fetch(id) when is_binary(id) do
    case Enum.find(tools(), &(&1.id == id)) do
      nil -> {:error, :unknown_tool}
      tool -> {:ok, tool}
    end
  end

  def provider_schemas(permissions) when is_list(permissions) do
    tools()
    |> Enum.filter(&permitted?(&1, permissions))
    |> Enum.map(fn tool ->
      %{
        type: "function",
        function: %{
          name: tool.id,
          description: Map.get(tool, :description, tool.id),
          parameters: tool.input_schema
        }
      }
    end)
  end

  def permitted?(tool, permissions) do
    required = Map.get(tool, :permissions, [])
    Enum.all?(required, &(&1 in permissions))
  end

  defp validate!(tool) do
    required = [:id, :version, :risk, :input_schema, :handler]

    unless Enum.all?(required, &Map.has_key?(tool, &1)) and
             is_binary(tool.id) and tool.id != "" and is_integer(tool.version) and
             tool.version > 0 and tool.risk in @risk_levels and is_map(tool.input_schema) and
             is_function(tool.handler, 2) do
      raise ArgumentError, "invalid AI tool declaration: #{inspect(tool)}"
    end

    tool
  end
end
