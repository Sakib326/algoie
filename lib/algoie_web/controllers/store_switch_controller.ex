defmodule AlgoieWeb.StoreSwitchController do
  use AlgoieWeb, :controller

  def switch(conn, %{"store_id" => store_id}) do
    user = conn.assigns[:current_user]

    with user when not is_nil(user) <- user,
         {:ok, store} <- Algoie.Accounts.UserContext.find_store_access(user.id, store_id) do
      user_stores = Algoie.Accounts.UserContext.load_all_user_stores(user.id)
      tenant = store.tenant
      store_name = store.store_name

      slug =
        case Algoie.Repo.query!(
               "SELECT slug FROM public.store_registry WHERE store_id::text = $1 AND tenant_id = $2 LIMIT 1",
               [store_id, String.replace_leading(tenant, "tenant_", "")]
             ).rows do
          [[value]] -> value
          _ -> nil
        end

      conn =
        conn
        |> put_session("store_tenant", tenant)
        |> put_session("store_id", store_id)
        |> put_session("store_name", store_name)
        |> put_session("user_stores", user_stores)

      if slug do
        redirect(conn, external: AlgoieWeb.PublicURL.store(slug, "/dashboard"))
      else
        conn
        |> put_flash(:error, "Store domain not found")
        |> redirect(to: "/store-select")
      end
    else
      _ ->
        conn
        |> put_flash(:error, "You no longer have access to that store")
        |> redirect(to: "/store-select")
    end
  end
end
