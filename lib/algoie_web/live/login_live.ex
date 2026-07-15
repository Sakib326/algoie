defmodule AlgoieWeb.LoginLive do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign In")
     |> assign(
       :form,
       to_form(%{"email" => "", "password" => ""}, as: "user")
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: "user"))}
  end
end
