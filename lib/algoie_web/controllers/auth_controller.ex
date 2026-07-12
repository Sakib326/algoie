defmodule AlgoieWeb.AuthController do
  use AlgoieWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    # Store tenant in session if available from registration
    tenant = conn.private[:phoenix_flash]["tenant"] || get_session(conn, "store_tenant")

    conn =
      if tenant do
        put_session(conn, "store_tenant", tenant)
      else
        conn
      end

    conn
    |> store_in_session(user)
    |> redirect(to: "/dashboard")
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> redirect(to: "/sign-in")
  end

  def sign_out(conn, _params) do
    conn
    |> clear_session(:algoie)
    |> put_flash(:info, "Signed out successfully")
    |> redirect(to: "/")
  end
end
