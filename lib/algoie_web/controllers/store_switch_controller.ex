defmodule AlgoieWeb.StoreSwitchController do
  use AlgoieWeb, :controller

  def switch(conn, %{"store_id" => store_id}) do
    user_stores = get_session(conn, "user_stores") || []

    case Enum.find(user_stores, fn store ->
           store_id_value = store["store_id"] || Map.get(store, :store_id)
           store_id_value == store_id
         end) do
      nil ->
        conn
        |> put_flash(:error, "Store not found")
        |> redirect(to: "/store-select")

      store ->
        tenant = store["tenant"] || Map.get(store, :tenant)
        store_name = store["store_name"] || Map.get(store, :store_name)

        conn
        |> put_session("store_tenant", tenant)
        |> put_session("store_id", store_id)
        |> put_session("store_name", store_name)
        |> redirect(to: "/dashboard")
    end
  end
end
