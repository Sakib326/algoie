defmodule AlgoieWeb.Live.OnDashboardMount do
  @moduledoc """
  OnMount hook for dashboard routes.
  Loads current_user from session, loads their store context, and redirects to sign-in if not authenticated.
  """

  import Phoenix.LiveView, only: [redirect: 2]
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, redirect(socket, to: "/sign-in")}

      user ->
        tenant = user.default_tenant

        if tenant do
          # Query the user's store in their default tenant
          case Ash.read(Algoie.Accounts.StoreStaff,
                 tenant: tenant,
                 query: [filter: [user_id: user.id]],
                 authorize?: false
               ) do
            {:ok, [staff | _]} ->
              socket =
                socket
                |> assign(:tenant, tenant)
                |> assign(:store_id, staff.store_id)
                |> assign(:current_scope, %{user: user})

              {:cont, socket}

            _ ->
              {:halt, redirect(socket, to: "/register")}
          end
        else
          {:halt, redirect(socket, to: "/register")}
        end
    end
  end
end
