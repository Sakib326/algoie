defmodule AlgoieWeb.Plugs.StoreSlugPlug do
  @moduledoc """
  Resolves store-slug.yourdomain.com → Store by slug → sets Ash tenant context.

  Options:
    - `:require_subdomain` (default: false) — when true, halts with 404 if no subdomain is detected.
      Used in the `:store` pipeline to ensure storefront routes are only accessible via subdomain.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    require_subdomain? = Keyword.get(opts, :require_subdomain, false)

    case extract_store_slug(conn) do
      nil ->
        if require_subdomain? do
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(
            404,
            "<h1>Store not found</h1><p>Storefront is only accessible via a store subdomain.</p>"
          )
          |> halt()
        else
          conn
        end

      slug ->
        case Algoie.Stores.lookup_store_by_slug(slug) do
          {:ok, %{tenant_id: tenant_id, store_id: store_id}} ->
            schema_name = "tenant_#{tenant_id}"

            conn
            |> Ash.PlugHelpers.set_tenant(schema_name)
            |> Ash.PlugHelpers.set_context(%{store_id: store_id})
            |> put_session(:store_tenant, schema_name)
            |> put_session(:store_id, store_id)

          {:error, :not_found} ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(404, "Store not found")
            |> halt()
        end
    end
  end

  defp extract_store_slug(conn) do
    host = conn.host
    domain = Application.get_env(:algoie, :apex_host, "localhost")

    # Strip port if present (e.g. "store.localhost:4000" → "store.localhost")
    host = String.split(host, ":") |> List.first()

    case String.replace_suffix(host, ".#{domain}", "") do
      ^host -> nil
      slug -> slug
    end
  end
end
