defmodule AlgoieWeb.Live.OnStoreMount do
  @moduledoc """
  OnMount hook that reads tenant and store_id from the Plug session
  (set by StoreSlugPlug) and makes them available as socket assigns.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    tenant = session["store_tenant"]
    store_id = session["store_id"]

    store =
      case Ash.get(Algoie.Stores.Store, store_id, tenant: tenant, authorize?: false) do
        {:ok, store} -> store
        _ -> nil
      end

    current_customer =
      case session["storefront_customer_id"] do
        nil ->
          nil

        id ->
          case Algoie.Storefront.CustomerAccounts.get(tenant, store_id, id) do
            {:ok, customer} -> customer
            _ -> nil
          end
      end

    {:cont,
     socket
     |> assign(:tenant, tenant)
     |> assign(:store_id, store_id)
     |> assign(:store, store)
     |> assign(:current_customer, current_customer)}
  end
end
