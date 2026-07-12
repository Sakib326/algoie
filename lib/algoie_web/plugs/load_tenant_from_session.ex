defmodule AlgoieWeb.Plugs.LoadTenantFromSession do
  @moduledoc """
  Reads the tenant schema name from the session and sets the Ash tenant context.
  Must run before `load_from_session` so user records can be loaded from the correct schema.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "store_tenant") do
      nil -> conn
      tenant -> Ash.PlugHelpers.set_tenant(conn, tenant)
    end
  end
end
