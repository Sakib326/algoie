defmodule AlgoieWeb.Plugs.CacheRawBody do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache(conn, body)}
      {:more, body, conn} -> {:more, body, cache(conn, body)}
      other -> other
    end
  end

  defp cache(conn, body) do
    previous = conn.assigns[:raw_body] || ""
    Plug.Conn.assign(conn, :raw_body, previous <> body)
  end
end
