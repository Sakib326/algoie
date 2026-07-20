defmodule AlgoieWeb.Live.OnUserMount do
  @moduledoc "Loads a global user and their current store memberships for apex account pages."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, redirect(socket, to: "/sign-in")}

      user ->
        {:cont,
         socket
         |> assign(:user_stores, Algoie.Accounts.UserContext.load_all_user_stores(user.id))
         |> assign(:user_tenants, Algoie.Accounts.TenantPortal.list_for_user(user.id))
         |> assign(:current_scope, %{user: user})}
    end
  end
end
