defmodule AlgoieWeb.Plugs.StoreSlugPlug do
  @moduledoc """
  Resolves store-slug.yourdomain.com → Store by slug → sets Ash tenant context.

  When a subdomain is detected and the path is "/", redirects to "/products"
  to serve the storefront home without conflicting with the platform "/" route.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_store_slug(conn) do
      nil ->
        conn

      slug ->
        case Algoie.Stores.lookup_store_by_slug(slug) do
          {:ok, %{tenant_id: tenant_id, store_id: store_id}} ->
            schema_name = "tenant_#{tenant_id}"

            conn =
              conn
              |> Ash.PlugHelpers.set_tenant(schema_name)
              |> Ash.PlugHelpers.set_context(%{store_id: store_id})
              |> put_session(:store_tenant, schema_name)
              |> put_session(:store_id, store_id)

            # If path is "/", redirect to the storefront home
            # to avoid conflicting with the platform "/" route
            if conn.request_path == "/" do
              conn
              |> put_resp_header("location", "/store")
              |> send_resp(302, "")
              |> halt()
            else
              conn
            end

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
    domain = System.get_env("APP_DOMAIN") || "localhost"

    case String.replace_suffix(host, ".#{domain}", "") do
      ^host -> nil
      slug -> slug
    end
  end
end
