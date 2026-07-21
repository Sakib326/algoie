defmodule AlgoieWeb.AiAssistantLive do
  use AlgoieWeb, :live_view

  alias Algoie.AI.Orchestrator
  alias Algoie.PlatformAISettings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
      |> assign(:page_title, "AI Assistant")
      |> assign(:active, :assistant)
      |> assign(:messages, [])
      |> assign(:loading, false)
      |> assign(:ai_enabled, PlatformAISettings.configured?(PlatformAISettings.get()))
      |> assign(:form, to_form(%{"instruction" => ""}, as: :assistant))}
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
        messages = socket.assigns.messages ++ [%{role: :user, content: instruction}]

        socket =
          socket
          |> assign(:messages, messages)
          |> assign(:loading, true)
          |> assign(:form, to_form(%{"instruction" => ""}, as: :assistant))

        case Orchestrator.respond(instruction, %{
               store_name: socket.assigns.store_name,
               store_id: socket.assigns.store_id,
               tenant: socket.assigns.tenant,
               role: socket.assigns.store_role,
               actor: socket.assigns.current_user,
               permissions: socket.assigns.store_permissions,
               messages: socket.assigns.messages
             }) do
          {:ok, %{content: response}} ->
            {:noreply,
             socket
             |> assign(:messages, messages ++ [%{role: :assistant, content: response}])
             |> assign(:loading, false)}

          {:error, :not_configured_or_model_not_allowed} ->
            {:noreply,
             socket
             |> assign(:ai_enabled, false)
             |> assign(:loading, false)
             |> put_flash(
               :error,
               "AI configuration is incomplete or its selected model is not allowed."
             )}

          {:error, :monthly_budget_exceeded} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> put_flash(:error, "Monthly AI budget has been exceeded. Contact your admin.")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> put_flash(:error, "The AI gateway could not complete this request.")}
        end
    end
  end
end
