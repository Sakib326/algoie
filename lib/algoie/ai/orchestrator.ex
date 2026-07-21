defmodule Algoie.AI.Orchestrator do
  @moduledoc """
  Bounded MVP chat orchestrator.

  It sends registered AI tools to the provider so the model can request
  structured actions. Tool calls are executed locally via ToolExecutor
  and the results are fed back into the conversation.
  """

  alias Algoie.AI.{OpenRouterClient, ToolExecutor, ToolRegistry, UsageTracker}
  alias Algoie.PlatformAISettings

  @max_tool_rounds 5

  @base_prompt """
  You are Algoie Assistant, a supervised ecommerce operations assistant.
  Be concise and helpful. Answer questions about store operations, best practices,
  and provide guidance. You cannot directly access or modify store data.
  """

  @tools_prompt """

  AVAILABLE TOOLS — you MUST use them when the user asks about store data:
  - list_products: search/filter products by status. Use when asked about products.
  - list_orders: search/filter orders by status. Use when asked about orders.
  - check_inventory: check stock levels, optionally filter low stock. Use when asked about stock/inventory/availability.

  RULES:
  - ALWAYS call a tool when the user asks about products, orders, inventory, or stock.
  - NEVER say "I cannot access" or "I don't have access" — you DO have tools.
  - NEVER make up data. Always call a tool to get real data.
  - You may call multiple tools in sequence if needed.
  - Only call tools that are provided to you in the function list.
  """

  def respond(instruction, context) when is_binary(instruction) and is_map(context) do
    settings = PlatformAISettings.get()

    case UsageTracker.check_budget!(settings) do
      :ok ->
        tools = tool_schemas(context)

        system_prompt =
          if tools != [], do: @base_prompt <> @tools_prompt, else: @base_prompt

        messages =
          [%{role: "system", content: system_prompt}] ++
            conversation_messages(context) ++
            [%{role: "user", content: scoped_instruction(instruction, context)}]

        chat_with_tools(messages, tools, context, 0, settings)

      {:error, :monthly_budget_exceeded} ->
        {:error, :monthly_budget_exceeded}
    end
  end

  defp chat_with_tools(messages, tools, context, round, _settings) when round >= @max_tool_rounds do
    case OpenRouterClient.chat(messages, tools: tools) do
      {:ok, response} ->
        track_usage(response, context)
        response_content(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp chat_with_tools(messages, tools, context, round, settings) do
    case OpenRouterClient.chat(messages, tools: tools) do
      {:ok, response} ->
        track_usage(response, context)

        case extract_message(response) do
          {:ok, %{"tool_calls" => [_ | _]} = message} ->
            handle_tool_calls(message, messages, tools, context, round, settings)

          {:ok, message} ->
            {:ok, %{content: message["content"], provider_response: response}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_tool_calls(message, messages, tools, context, round, settings) do
    tool_context = build_tool_context(context)
    require Logger

    tool_results =
      Enum.map(message["tool_calls"], fn tool_call ->
        id = tool_call["id"]
        name = get_in(tool_call, ["function", "name"])
        args = decode_tool_args(tool_call)

        Logger.debug("Tool call: #{name}(#{inspect(args)})")

        result =
          case ToolExecutor.execute(name, args, tool_context) do
            {:ok, result} ->
              Logger.debug("Tool #{name} OK: #{inspect(result) |> String.slice(0, 200)}")
              %{result: Jason.encode!(result)}

            {:error, reason} ->
              Logger.debug("Tool #{name} ERROR: #{inspect(reason)}")
              %{error: inspect(reason)}

            {:approval_required, preview} ->
              Logger.debug("Tool #{name} needs approval: #{inspect(preview)}")
              %{approval_required: preview}
          end

        %{
          role: "tool",
          tool_call_id: id,
          content: Jason.encode!(result)
        }
      end)

    updated_messages =
      messages ++
        [%{role: "assistant", content: message["content"], tool_calls: message["tool_calls"]}] ++
        tool_results

    chat_with_tools(updated_messages, tools, context, round + 1, settings)
  end

  defp decode_tool_args(tool_call) do
    case get_in(tool_call, ["function", "arguments"]) || tool_call["function"]["arguments"] do
      args when is_binary(args) ->
        case Jason.decode(args) do
          {:ok, parsed} -> parsed
          _ -> %{}
        end

      args when is_map(args) ->
        args

      _ ->
        %{}
    end
  end

  defp extract_message(%{"choices" => [%{"message" => msg} | _]}), do: {:ok, msg}
  defp extract_message(_), do: {:error, :invalid_provider_response}

  defp build_tool_context(context) do
    %{
      actor: Map.get(context, :actor),
      tenant: Map.get(context, :tenant),
      store_id: Map.get(context, :store_id),
      permissions: Map.get(context, :permissions, [])
    }
  end

  defp track_usage(%{"model" => model, "usage" => usage}, context) do
    UsageTracker.record(model, usage, context)
  end

  defp track_usage(_, _), do: :ok

  defp tool_schemas(context) do
    permissions = Map.get(context, :permissions, [])
    ToolRegistry.provider_schemas(permissions)
  end

  defp scoped_instruction(instruction, context) do
    """
    Current store: #{context.store_name}. The signed-in role is #{context.role}.
    User instruction: #{instruction}
    """
  end

  defp conversation_messages(context) do
    context
    |> Map.get(:messages, [])
    |> Enum.take(-12)
    |> Enum.flat_map(fn
      %{role: role, content: content} when role in [:user, :assistant] and is_binary(content) ->
        [%{role: Atom.to_string(role), content: content}]

      _ ->
        []
    end)
  end

  defp response_content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content),
       do: {:ok, %{content: content}}

  defp response_content(_response), do: {:error, :invalid_provider_response}
end
