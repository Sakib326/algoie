defmodule AlgoieWeb.Plugs.LoadStorefrontCustomer do
  @moduledoc "Loads the signed-in customer within the resolved tenant and store."

  import Plug.Conn

  alias Algoie.Storefront.CustomerAccounts

  def init(opts), do: opts

  def call(conn, _opts) do
    customer =
      case get_session(conn, "storefront_customer_id") do
        nil ->
          nil

        id ->
          case CustomerAccounts.get(
                 get_session(conn, "store_tenant"),
                 get_session(conn, "store_id"),
                 id
               ) do
            {:ok, customer} -> customer
            _ -> nil
          end
      end

    assign(conn, :current_customer, customer)
  end
end
