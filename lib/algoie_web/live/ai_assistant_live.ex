defmodule AlgoieWeb.AiAssistantLive do
  use AlgoieWeb, :live_view

  alias Algoie.AI.{Conversations, Orchestrator, ToolExecutor}
  alias Algoie.AI.Tools.StoreResources
  alias Algoie.Accounts.{StorePermissions, UserContext}
  alias Algoie.PlatformAISettings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI Assistant")
     |> assign(:active, :assistant)
     |> assign(:messages, [])
     |> assign(:messages_cursor, nil)
     |> assign(:messages_has_more?, false)
     |> assign(:conversation_id, nil)
     |> assign(:conversations, [])
     |> assign(:loading, false)
     |> assign(:activity, nil)
     |> assign(:activities, [])
     |> assign(:streaming_response, "")
     |> assign(:pending_approvals, [])
     |> assign(:ai_enabled, PlatformAISettings.configured?(PlatformAISettings.get()))
     |> assign(:capabilities, capabilities(socket.assigns.store_permissions))
     |> assign(:form, to_form(%{"instruction" => ""}, as: :assistant))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    conversation =
      case params["conversation"] do
        nil -> nil
        id -> Conversations.get(id, socket.assigns.current_user.id, socket.assigns.store_id)
      end

    message_page =
      if conversation,
        do: Conversations.message_page(conversation.id),
        else: %{messages: [], cursor: nil, has_more?: false}

    {:noreply,
     socket
     |> assign(:conversation_id, conversation && conversation.id)
     |> assign(:messages, message_page.messages)
     |> assign(:messages_cursor, message_page.cursor)
     |> assign(:messages_has_more?, message_page.has_more?)
     |> assign(
       :pending_approvals,
       if(conversation,
         do:
           Conversations.pending_actions(
             conversation.id,
             socket.assigns.current_user.id,
             socket.assigns.store_id
           ),
         else: []
       )
     )
     |> load_conversations()}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    {:noreply, push_patch(socket, to: "/dashboard/assistant")}
  end

  def handle_event("open_chat", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/dashboard/assistant?conversation=#{id}")}
  end

  def handle_event("delete_chat", %{"id" => id}, socket) do
    Conversations.delete(id, socket.assigns.current_user.id, socket.assigns.store_id)

    if socket.assigns.conversation_id == id do
      {:noreply, push_patch(socket, to: "/dashboard/assistant")}
    else
      {:noreply, load_conversations(socket)}
    end
  end

  def handle_event("use_prompt", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :form, to_form(%{"instruction" => prompt}, as: :assistant))}
  end

  def handle_event("load_older_messages", _params, socket) do
    if socket.assigns.conversation_id && socket.assigns.messages_has_more? &&
         socket.assigns.messages_cursor do
      page =
        Conversations.message_page(
          socket.assigns.conversation_id,
          socket.assigns.messages_cursor
        )

      {:noreply,
       socket
       |> assign(:messages, page.messages ++ socket.assigns.messages)
       |> assign(:messages_cursor, page.cursor)
       |> assign(:messages_has_more?, page.has_more?)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reject_action", _params, socket) do
    Enum.each(socket.assigns.pending_approvals, fn approval ->
      Conversations.resolve_action(
        approval.id,
        socket.assigns.current_user.id,
        socket.assigns.store_id,
        :rejected
      )
    end)

    {:noreply, assign(socket, :pending_approvals, [])}
  end

  def handle_event("approve_action", _params, %{assigns: %{pending_approvals: []}} = socket),
    do: {:noreply, socket}

  def handle_event("approve_action", _params, socket) do
    [approval | remaining] = socket.assigns.pending_approvals

    with {:ok, access} <-
           UserContext.find_store_access(socket.assigns.current_user.id, socket.assigns.store_id),
         true <- access.tenant == socket.assigns.tenant,
         context <- %{
           actor: socket.assigns.current_user,
           tenant: socket.assigns.tenant,
           store_id: socket.assigns.store_id,
           role: access.role,
           permissions: access.permissions
         },
         {:ok, result} <-
           ToolExecutor.execute_approved(approval.tool_id, approval.arguments, context) do
      response = action_success(approval, result)
      machine_result = Jason.encode!(result)

      {:ok, _} = Conversations.add_message(socket.assigns.conversation_id, :assistant, response)

      Conversations.resolve_action(
        approval.id,
        socket.assigns.current_user.id,
        socket.assigns.store_id,
        :approved
      )

      socket =
        socket
        |> assign(:pending_approvals, remaining)
        |> assign(:messages, socket.assigns.messages ++ [%{role: :assistant, content: response}])
        |> load_conversations()
        |> put_flash(:info, "Approved action completed")

      if remaining == [],
        do: continue_after_approval(socket, machine_result, access),
        else: {:noreply, socket}
    else
      error ->
        Conversations.resolve_action(
          approval.id,
          socket.assigns.current_user.id,
          socket.assigns.store_id,
          :failed
        )

        action_failure(socket, approval, error)
    end
  end

  @impl true
  def handle_event("ask", %{"assistant" => %{"instruction" => instruction}}, socket) do
    instruction = String.trim(instruction)

    cond do
      instruction == "" ->
        {:noreply, put_flash(socket, :error, "Enter an instruction first.")}

      not socket.assigns.ai_enabled ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The AI gateway is not enabled. A SaaS admin must configure OpenRouter first."
         )}

      true ->
        history = socket.assigns.messages
        progress_pid = self()

        {:ok, conversation} =
          case socket.assigns.conversation_id do
            nil ->
              Conversations.start(
                socket.assigns.current_user.id,
                socket.assigns.store_id,
                socket.assigns.tenant,
                instruction
              )

            id ->
              {:ok, %{id: id}}
          end

        {:ok, _} = Conversations.add_message(conversation.id, :user, instruction)
        messages = history ++ [%{role: :user, content: instruction}]

        socket =
          socket
          |> assign(:messages, messages)
          |> assign(:loading, true)
          |> assign(:activity, "Understanding your request and checking live store data…")
          |> assign(:activities, ["Understanding your request and checking live store data…"])
          |> assign(:streaming_response, "")
          |> assign(:form, to_form(%{"instruction" => ""}, as: :assistant))

        {:ok, access} =
          UserContext.find_store_access(socket.assigns.current_user.id, socket.assigns.store_id)

        context = %{
          store_name: socket.assigns.store_name,
          store_id: socket.assigns.store_id,
          tenant: socket.assigns.tenant,
          role: socket.assigns.store_role,
          actor: socket.assigns.current_user,
          permissions: access.permissions,
          messages: history,
          progress_pid: progress_pid
        }

        {:noreply,
         start_async(socket, :assistant_response, fn ->
           {conversation.id, messages, Orchestrator.respond(instruction, context)}
         end)}
    end
  end

  @impl true
  def handle_async(
        :assistant_response,
        {:ok, {conversation_id, messages, {:ok, %{content: response} = result}}},
        socket
      ) do
    {:ok, _} = Conversations.add_message(conversation_id, :assistant, response)

    {:ok, approvals} =
      Conversations.replace_pending_actions(
        conversation_id,
        socket.assigns.current_user.id,
        socket.assigns.store_id,
        Map.get(result, :approvals, [])
      )

    {:noreply,
     socket
     |> assign(:conversation_id, conversation_id)
     |> assign(:messages, messages ++ [%{role: :assistant, content: response}])
     |> assign(:pending_approvals, approvals)
     |> assign(:loading, false)
     |> assign(:activity, nil)
     |> assign(:streaming_response, "")
     |> load_conversations()
     |> push_patch(to: "/dashboard/assistant?conversation=#{conversation_id}")}
  end

  def handle_async(:assistant_response, {:ok, {_id, _messages, {:error, reason}}}, socket) do
    message =
      case reason do
        :monthly_budget_exceeded -> "The monthly AI budget has been reached."
        :not_configured_or_model_not_allowed -> "The configured AI model is unavailable."
        _ -> "I couldn’t complete that request. Please try again."
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:activity, nil)
     |> assign(:streaming_response, "")
     |> put_flash(:error, message)}
  end

  def handle_async(:assistant_response, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:activity, nil)
     |> assign(:streaming_response, "")
     |> put_flash(:error, "The assistant stopped unexpectedly. Please try again.")}
  end

  def handle_async(:assistant_continuation, {:ok, {:ok, %{content: content} = result}}, socket) do
    {:ok, _} = Conversations.add_message(socket.assigns.conversation_id, :assistant, content)

    {:ok, approvals} =
      Conversations.replace_pending_actions(
        socket.assigns.conversation_id,
        socket.assigns.current_user.id,
        socket.assigns.store_id,
        Map.get(result, :approvals, [])
      )

    {:noreply,
     socket
     |> assign(:messages, socket.assigns.messages ++ [%{role: :assistant, content: content}])
     |> assign(:pending_approvals, approvals)
     |> assign(:loading, false)
     |> assign(:activity, nil)
     |> assign(:streaming_response, "")
     |> load_conversations()}
  end

  def handle_async(:assistant_continuation, _result, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:activity, nil)
     |> assign(:streaming_response, "")
     |> put_flash(
       :error,
       "The action succeeded, but the assistant could not continue the remaining steps."
     )}
  end

  @impl true
  def handle_info({:assistant_activity, activity}, socket) do
    activities =
      (socket.assigns.activities ++ [activity])
      |> Enum.dedup()
      |> Enum.take(-8)

    {:noreply, socket |> assign(:activity, activity) |> assign(:activities, activities)}
  end

  def handle_info(:assistant_stream_reset, socket) do
    {:noreply, assign(socket, :streaming_response, "")}
  end

  def handle_info({:assistant_delta, delta}, socket) do
    {:noreply, update(socket, :streaming_response, &(&1 <> delta))}
  end

  defp load_conversations(socket) do
    assign(
      socket,
      :conversations,
      Conversations.list(socket.assigns.current_user.id, socket.assigns.store_id)
    )
  end

  defp continue_after_approval(socket, execution_result, access) do
    instruction =
      "The user approved the requested action and it completed with this result:\n#{execution_result}\nContinue the original request. Use another tool if another step is required; otherwise summarize the completed work. Do not repeat an action that already succeeded."

    progress_pid = self()

    context = %{
      store_name: socket.assigns.store_name,
      store_id: socket.assigns.store_id,
      tenant: socket.assigns.tenant,
      role: access.role,
      actor: socket.assigns.current_user,
      permissions: access.permissions,
      messages: socket.assigns.messages,
      progress_pid: progress_pid
    }

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:activity, "Continuing the remaining steps…")
      |> assign(:activities, ["Continuing the remaining steps…"])
      |> assign(:streaming_response, "")

    {:noreply,
     start_async(socket, :assistant_continuation, fn ->
       Orchestrator.respond(instruction, context)
     end)}
  end

  defp action_failure(socket, approval, error) do
    context = %{
      actor: socket.assigns.current_user,
      tenant: socket.assigns.tenant,
      store_id: socket.assigns.store_id,
      permissions: socket.assigns.store_permissions
    }

    content = action_error(error, approval, context)
    {:ok, _} = Conversations.add_message(socket.assigns.conversation_id, :assistant, content)

    {:noreply,
     socket
     |> assign(:pending_approvals, [])
     |> assign(:messages, socket.assigns.messages ++ [%{role: :assistant, content: content}])
     |> load_conversations()}
  end

  defp action_success(approval, result) do
    operation = approval.arguments["operation"] || success_operation(approval.tool_id)
    resource = approval.arguments["resource"] || success_resource(approval.tool_id)
    record = result[:result] || result["result"] || result
    name = record[:name] || record["name"] || record[:code] || record["code"]

    subject =
      [name && "**#{name}**", resource && String.replace(resource, "_", " ")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    details = success_details(operation, approval.arguments["attributes"] || %{})
    "Done — I #{past_tense(operation)} #{subject}.#{details}"
  end

  defp success_operation("create_order"), do: "create"
  defp success_operation(_tool_id), do: "complete"
  defp success_resource("create_order"), do: "order"
  defp success_resource("manage_store_settings"), do: "store settings"
  defp success_resource(_tool_id), do: nil

  defp past_tense("create"), do: "created"
  defp past_tense("update"), do: "updated"
  defp past_tense("delete"), do: "deleted"
  defp past_tense(operation), do: String.replace(operation || "completed", "_", " ")

  defp success_details("update", attrs) when map_size(attrs) > 0 do
    fields = attrs |> Map.keys() |> Enum.map_join(", ", &String.replace(&1, "_", " "))
    " Updated: #{fields}."
  end

  defp success_details(_operation, _attrs), do: ""

  defp approval_fields(arguments) do
    base =
      arguments
      |> Map.drop(["attributes"])
      |> Enum.map(fn {key, value} -> {humanize(key), display_value(value)} end)

    attributes =
      arguments
      |> Map.get("attributes", %{})
      |> Enum.map(fn {key, value} -> {humanize(key), display_value(value)} end)

    base ++ attributes
  end

  defp humanize(value), do: value |> String.replace("_", " ") |> String.capitalize()
  defp display_value(value) when is_list(value), do: Enum.map_join(value, ", ", &display_value/1)
  defp display_value(value) when is_map(value), do: "#{map_size(value)} configured values"
  defp display_value(nil), do: "Not set"
  defp display_value(value), do: to_string(value)

  defp action_error(false, _approval, _context),
    do: "I couldn’t run that action because your access changed. No store data was changed."

  defp action_error({:error, %Ash.Error.Forbidden{}}, _approval, _context),
    do:
      "I couldn’t run that action because your current role does not permit it. No store data was changed."

  defp action_error(
         {:error, _reason},
         %{arguments: %{"operation" => "delete", "resource" => "product", "id" => id}},
         context
       ),
       do: product_delete_error(StoreResources.deletion_blockers("product", id, context))

  defp action_error(
         {:error, _reason},
         %{arguments: %{"operation" => "delete", "resource" => resource}},
         _context
       ),
       do:
         "I couldn’t permanently delete that #{String.replace(resource, "_", " ")} because another store record still references it. No data was changed."

  defp action_error(
         {:error, reason},
         %{arguments: %{"operation" => operation, "resource" => resource}},
         _context
       ) do
    description =
      reason
      |> Ash.Error.to_error_class()
      |> Map.get(:errors, [])
      |> Enum.map(fn error -> Map.get(error, :message) || Exception.message(error) end)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()
      |> Enum.join(" ")
      |> case do
        "" -> "The supplied values did not pass validation."
        message -> message
      end

    "I couldn’t #{String.replace(operation, "_", " ")} the #{String.replace(resource, "_", " ")}. #{description} No store data was changed."
  end

  defp action_error(_error, _approval, _context),
    do: "I couldn’t complete the approved action. No store data was changed."

  defp product_delete_error(blockers) do
    details =
      [
        {blockers.historical_order_items, "historical order line item"},
        {blockers.variants, "variant"},
        {blockers.images, "product image"},
        {blockers.categories, "category assignment"},
        {blockers.tags, "tag assignment"},
        {blockers.collections, "collection assignment"}
      ]
      |> Enum.filter(fn {count, _label} -> count > 0 end)
      |> Enum.map_join("\n", fn {count, label} ->
        "- #{count} #{label}#{if count == 1, do: "", else: "s"}"
      end)

    note =
      if blockers.historical_order_items > 0 do
        "I won’t cascade-delete historical orders. The production-safe option is to keep the product **archived**, which removes it from sale while preserving invoices and reports."
      else
        "These non-historical relationships must be removed before permanent deletion. I can do that as a reviewed multi-step operation if you ask me to permanently remove the product and its related catalog data."
      end

    "I couldn’t permanently delete the product because the database found these dependencies:\n\n#{details}\n\n#{note}"
  end

  defp capabilities(permissions) do
    StorePermissions.all()
    |> Enum.reject(fn {permission, _label} -> permission == "ai.use" end)
    |> Enum.map(fn {permission, label} ->
      %{permission: permission, label: label, allowed?: permission in permissions}
    end)
  end
end
