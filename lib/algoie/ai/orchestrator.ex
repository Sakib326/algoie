defmodule Algoie.AI.Orchestrator do
  @moduledoc """
  Permission-aware store operations chat orchestrator.

  It sends registered AI tools to the provider so the model can request
  structured actions. Tool calls are executed locally via ToolExecutor
  and the results are fed back into the conversation.
  """

  alias Algoie.AI.{OpenRouterClient, ToolExecutor, ToolRegistry, UsageTracker}
  alias Algoie.PlatformAISettings

  @max_tool_rounds 5

  @base_prompt """
  You are Algoie, the signed-in user's ecommerce operations copilot.
  Be concise, practical, and action-oriented. Use only the tools provided in this request;
  they are already filtered to the user's current store permissions. Never imply that the
  user has a permission or capability that is not present. Never invent store data.
  If no provided tool can complete an operation, explain the limitation plainly and give
  the shortest safe path to finish it in the dashboard.

  RESPONSE FORMAT:
  - Present tool results for people, never as raw JSON or inspected structs.
  - Use short paragraphs, bullets, or a table only when a table materially improves comparison.
  - Every Markdown table row MUST be on its own line, with a valid separator row on its own line.
    Add a blank line before and after a table. Never emit an entire table on one line.
  - Keep tables compact (normally no more than 5 columns) and summarize the important finding.
  """

  @tools_prompt """

  RULES:
  - ALWAYS call the relevant tool when the user asks about live store data.
  - NEVER make up data. Always call a tool to get real data.
  - You may call multiple tools in sequence if needed.
  - Only call tools that are provided to you in the function list.
  - A missing tool may mean the user's role lacks permission. Do not suggest bypassing it.
  - Call create or update tools only when the user explicitly instructs you to make that change.
    Questions, analysis requests, and suggestions are never permission to mutate data.
  - Clear imperative instructions such as "create", "update", "do it", or "fix it" are authorization
    for ordinary reversible writes. Destructive, external-effect, and financial tools will be gated
    by the application and must not be described as completed until their tool result confirms it.
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

  defp chat_with_tools(messages, tools, context, round, _settings)
       when round >= @max_tool_rounds do
    case OpenRouterClient.chat(messages, tools: tools) do
      {:ok, response} ->
        track_usage(response, context)
        response_content(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp chat_with_tools(messages, tools, context, round, settings) do
    notify_progress(context, "Reviewing the latest store data and planning the next step…")

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

    executions =
      Enum.map(message["tool_calls"], fn tool_call ->
        id = tool_call["id"]
        name = get_in(tool_call, ["function", "name"])
        args = decode_tool_args(tool_call)

        notify_progress(context, tool_activity(name))

        Logger.debug("Tool call: #{name}(#{inspect(args)})")

        result =
          case ToolExecutor.execute(name, args, tool_context) do
            {:ok, result} ->
              Logger.debug("Tool #{name} OK: #{inspect(result) |> String.slice(0, 200)}")
              %{result: encode_tool_result(result)}

            {:error, reason} ->
              Logger.debug("Tool #{name} ERROR: #{inspect(reason)}")
              %{error: inspect(reason)}

            {:approval_required, preview} ->
              Logger.debug("Tool #{name} needs approval: #{inspect(preview)}")
              %{approval_required: preview}
          end

        %{id: id, name: name, args: args, result: result}
      end)

    pending = Enum.filter(executions, &Map.has_key?(&1.result, :approval_required))

    case pending do
      [] ->
        tool_results =
          Enum.map(executions, fn execution ->
            %{
              role: "tool",
              tool_call_id: execution.id,
              content: Jason.encode!(execution.result)
            }
          end)

        updated_messages =
          messages ++
            [%{role: "assistant", content: message["content"], tool_calls: message["tool_calls"]}] ++
            tool_results

        chat_with_tools(updated_messages, tools, context, round + 1, settings)

      pending ->
        approvals =
          Enum.map(pending, fn execution ->
            %{
              tool_id: execution.name,
              arguments: execution.args,
              preview: execution.result.approval_required
            }
          end)

        preview = hd(approvals).preview

        {:ok,
         %{
           content: approval_message(preview, length(approvals)),
           approvals: approvals
         }}
    end
  end

  defp approval_message(preview, count) do
    operation = get_in(preview, [:arguments, "operation"]) || "perform this action"
    resource = get_in(preview, [:arguments, "resource"])
    target = if resource, do: " #{resource}", else: ""

    suffix = if count > 1, do: " There are #{count} actions to review in this step.", else: ""

    "I’m ready to **#{String.replace(operation, "_", " ")}#{target}**. Please review and approve the action below before I change store data.#{suffix}"
  end

  defp notify_progress(%{progress_pid: pid}, message) when is_pid(pid),
    do: send(pid, {:assistant_activity, message})

  defp notify_progress(_context, _message), do: :ok

  defp tool_activity("list_products"), do: "Reading products and variants…"
  defp tool_activity("list_orders"), do: "Checking orders…"
  defp tool_activity("check_inventory"), do: "Checking live inventory…"
  defp tool_activity("query_catalog"), do: "Inspecting the catalog…"
  defp tool_activity("query_customers"), do: "Looking up customers…"
  defp tool_activity("query_discounts"), do: "Checking discounts and delivery rates…"
  defp tool_activity("manage_" <> _rest), do: "Preparing a reviewed store change…"
  defp tool_activity("create_order"), do: "Validating the order and stock…"
  defp tool_activity(_name), do: "Working with live store data…"

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

  defp encode_tool_result(result) do
    case Jason.encode(result) do
      {:ok, encoded} ->
        encoded

      {:error, reason} ->
        Jason.encode!(%{
          error: "Tool returned an invalid result",
          detail: Exception.message(reason)
        })
    end
  end

  defp extract_message(%{"choices" => [%{"message" => msg} | _]}), do: {:ok, msg}
  defp extract_message(_), do: {:error, :invalid_provider_response}

  defp build_tool_context(context) do
    %{
      actor: Map.get(context, :actor),
      tenant: Map.get(context, :tenant),
      store_id: Map.get(context, :store_id),
      role: Map.get(context, :role),
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
    Effective permissions: #{Enum.join(Map.get(context, :permissions, []), ", ")}.
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
