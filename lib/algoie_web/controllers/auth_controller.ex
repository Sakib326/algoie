defmodule AlgoieWeb.AuthController do
  use AlgoieWeb, :controller
  use AshAuthentication.Phoenix.Controller

  import Ecto.Query
  require Ash.Query

  def success(conn, _activity, user, _token) do
    case resolve_user_store_context(user) do
      {:ok, %{tenant: tenant, store_id: store_id, store_name: store_name, stores: stores}} ->
        conn
        |> store_in_session(user)
        |> put_session("store_tenant", tenant)
        |> put_session("store_id", store_id)
        |> put_session("store_name", store_name)
        |> put_session("user_stores", stores)
        |> redirect(to: "/dashboard")

      {:error, :no_store} ->
        conn
        |> store_in_session(user)
        |> redirect(to: "/dashboard")

      {:error, _reason} ->
        conn
        |> store_in_session(user)
        |> redirect(to: "/dashboard")
    end
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
    # Get all store_staff memberships across all tenants
    # We need to query each tenant schema the user might belong to
    case get_user_tenants(user.id) do
      [] ->
        {:error, :no_store}

      tenants ->
        find_first_store(user.id, tenants)
    end
  end

  defp get_user_tenants(user_id) do
    # Get all tenants
    case Algoie.Repo.all(from(t in "tenants", prefix: "public", select: t.id)) do
      tenant_ids ->
        Enum.filter(tenant_ids, fn tenant_id ->
          schema = "tenant_#{tenant_id}"

          case Ecto.Adapters.SQL.query(
                 Algoie.Repo,
                 "SELECT 1 FROM \"#{schema}\".store_staff WHERE user_id = $1 LIMIT 1",
                 [user_id]
               ) do
            {:ok, %{rows: [_ | _]}} -> true
            _ -> false
          end
        end)
    end
  end

  defp find_first_store(user_id, [tenant_id | rest]) do
    schema = "tenant_#{tenant_id}"

    case Ecto.Adapters.SQL.query(
           Algoie.Repo,
           "SELECT ss.store_id, s.name FROM \"#{schema}\".store_staff ss JOIN \"#{schema}\".stores s ON s.id = ss.store_id WHERE ss.user_id = $1 LIMIT 1",
           [user_id]
         ) do
      {:ok, %{rows: [[store_id, store_name] | _]}} ->
        # Build list of all stores for this user across all tenants
        all_stores = get_all_user_stores(user_id, [tenant_id | rest])

        {:ok,
         %{
           tenant: schema,
           store_id: store_id,
           store_name: store_name,
           stores: all_stores
         }}

      _ ->
        find_first_store(user_id, rest)
    end
  end

  defp find_first_store(_user_id, []), do: {:error, :no_store}

  defp get_all_user_stores(user_id, tenants) do
    Enum.flat_map(tenants, fn tenant_id ->
      schema = "tenant_#{tenant_id}"

      case Ecto.Adapters.SQL.query(
             Algoie.Repo,
             "SELECT ss.store_id, s.name, ss.role FROM \"#{schema}\".store_staff ss JOIN \"#{schema}\".stores s ON s.id = ss.store_id WHERE ss.user_id = $1",
             [user_id]
           ) do
        {:ok, %{rows: rows}} ->
          Enum.map(rows, fn [store_id, store_name, role] ->
            %{store_id: store_id, store_name: store_name, tenant: schema, role: role}
          end)

        _ ->
          []
      end
    end)
  end
end
