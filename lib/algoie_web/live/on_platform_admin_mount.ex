defmodule AlgoieWeb.Live.OnPlatformAdminMount do
  @moduledoc "Restricts apex administration to configured SaaS owner accounts."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, redirect(socket, to: "/sign-in")}

      user ->
        email = user.email |> to_string() |> String.downcase()

        if email in Application.get_env(:algoie, :platform_admin_emails, []) do
          {:cont, assign(socket, :current_scope, %{user: user})}
        else
          {:halt,
           socket
           |> put_flash(
             :error,
             "This account is not authorized for SaaS administration. Check PLATFORM_ADMIN_EMAILS and restart the server."
           )
           |> redirect(to: "/")}
        end
    end
  end
end
