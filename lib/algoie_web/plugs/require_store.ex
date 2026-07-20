defmodule AlgoieWeb.Plugs.RequireStore do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(%{assigns: %{store: _store}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Tenant dashboard requires a store subdomain")
    |> halt()
  end
end
