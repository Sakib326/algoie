defmodule AlgoieWeb.AuthController do
  use AlgoieWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias Algoie.Accounts.UserContext

  def success(conn, _activity, user, _token) do
    cond do
      conn.assigns[:store] ->
        store = conn.assigns.store
        tenant = get_session(conn, "store_tenant")

        conn
        |> store_in_session(user)
        |> put_session("store_tenant", tenant)
        |> put_session("store_id", store.id)
        |> put_session("store_name", store.name)
        |> redirect(to: "/dashboard")

      platform_admin?(user) ->
        conn |> store_in_session(user) |> redirect(to: "/dashboard")

      true ->
        tenant_success(conn, user)
    end
  end

  defp tenant_success(conn, user) do
    case Algoie.Accounts.TenantPortal.list_for_user(user.id) do
      [tenant | _] ->
        conn
        |> store_in_session(user)
        |> redirect(to: "/tenant/#{tenant.slug}/dashboard")

      [] ->
        legacy_store_success(conn, user)
    end
  end

  defp legacy_store_success(conn, user) do
    case resolve_user_store_context(user) do
      {:ok, %{tenant: tenant, store_id: store_id, store_name: store_name, stores: stores}} ->
        conn
        |> store_in_session(user)
        |> put_session("store_tenant", tenant)
        |> put_session("store_id", store_id)
        |> put_session("store_name", store_name)
        |> put_session("user_stores", stores)
        |> redirect(external: store_dashboard_url(conn, store_id))

      _ ->
        conn |> store_in_session(user) |> redirect(to: "/")
    end
  end

  defp platform_admin?(user) do
    String.downcase(to_string(user.email)) in Application.get_env(
      :algoie,
      :platform_admin_emails,
      []
    )
  end

  defp store_dashboard_url(_conn, store_id) do
    slug =
      case Algoie.Repo.query!(
             "SELECT slug FROM public.store_registry WHERE store_id::text = $1 LIMIT 1",
             [store_id]
           ).rows do
        [[slug]] -> slug
        _ -> raise "Store registry missing for #{store_id}"
      end

    AlgoieWeb.PublicURL.store(slug, "/dashboard")
  end

  def failure(conn, _activity, reason) do
    require Logger
    Logger.error("Auth failure: #{inspect(reason)}")

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

  defp resolve_user_store_context(user) do
    case UserContext.load_all_user_stores(user.id) do
      [] ->
        {:error, :no_store}

      [first | _] = stores ->
        {:ok,
         %{
           tenant: first.tenant,
           store_id: first.store_id,
           store_name: first.store_name,
           stores: stores
         }}
    end
  end
end
