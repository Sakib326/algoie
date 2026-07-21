defmodule Algoie.AI.ToolExecutor do
  @moduledoc """
  Executes only registered tools and stops consequential calls at an approval gate.
  """

  alias Algoie.AI.ToolRegistry

  @approval_risks [:external_effect, :destructive_or_financial]

  def execute(id, arguments, context)
      when is_binary(id) and is_map(arguments) and is_map(context) do
    with :ok <- validate_context(context),
         {:ok, tool} <- ToolRegistry.fetch(id),
         true <- ToolRegistry.permitted?(tool, Map.get(context, :permissions, [])),
         :ok <- validate_arguments(tool.input_schema, arguments) do
      if approval_required?(tool, arguments) do
        {:approval_required, approval_preview(tool, arguments)}
      else
        tool.handler.(arguments, context)
      end
    else
      false -> {:error, :not_authorized}
      {:error, _reason} = error -> error
    end
  end

  def execute_approved(id, arguments, context)
      when is_binary(id) and is_map(arguments) and is_map(context) do
    with :ok <- validate_context(context),
         {:ok, tool} <- ToolRegistry.fetch(id),
         true <- ToolRegistry.permitted?(tool, Map.get(context, :permissions, [])),
         :ok <- validate_arguments(tool.input_schema, arguments),
         true <- tool.risk in [:write | @approval_risks] do
      tool.handler.(arguments, context)
    else
      false -> {:error, :not_authorized}
      {:error, _reason} = error -> error
    end
  end

  defp validate_context(%{actor: actor, tenant: tenant, store_id: store_id})
       when not is_nil(actor) and is_binary(tenant) and is_binary(store_id),
       do: :ok

  defp validate_context(_context), do: {:error, :invalid_execution_context}

  # Tool schemas are deliberately small in MVP. Domain tools can add stricter
  # validation before invoking their Ash action.
  defp validate_arguments(%{"type" => "object", "required" => required}, arguments)
       when is_list(required) do
    if Enum.all?(required, &Map.has_key?(arguments, &1)),
      do: :ok,
      else: {:error, :invalid_arguments}
  end

  defp validate_arguments(%{"type" => "object"}, _arguments), do: :ok
  defp validate_arguments(_schema, _arguments), do: {:error, :invalid_tool_schema}

  defp approval_preview(tool, arguments) do
    %{tool_id: tool.id, tool_version: tool.version, risk: tool.risk, arguments: arguments}
  end

  defp approval_required?(%{risk: risk}, _arguments) when risk in @approval_risks, do: true

  defp approval_required?(%{risk: :write}, %{"operation" => "delete"}), do: true

  defp approval_required?(%{risk: :write}, %{
         "operation" => operation,
         "attributes" => attributes
       })
       when operation in ["update_status", "update_payment", "update_fulfillment"] do
    attributes["status"] in ["cancelled", "fulfilled"] or
      attributes["payment_status"] == "refunded" or
      attributes["fulfillment_status"] in ["delivered", "returned"]
  end

  defp approval_required?(%{risk: :write}, %{"attributes" => %{"status" => "inactive"}}),
    do: true

  defp approval_required?(_tool, _arguments), do: false
end
