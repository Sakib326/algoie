defmodule AlgoieWeb.OrderLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.Order

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_orders(socket)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Orders")}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    orders = filter_orders(socket, status)
    {:noreply, assign(socket, :orders, orders)}
  end

  defp load_orders(socket) do
    case Ash.read(Order, tenant: socket.assigns.tenant, authorize?: false) do
      {:ok, orders} ->
        assign(socket, :orders, orders)

      _ ->
        assign(socket, :orders, [])
    end
  end

  defp filter_orders(socket, "all"), do: load_orders(socket)

  defp filter_orders(socket, status) do
    case Ash.read(Order,
           tenant: socket.assigns.tenant,
           query: [filter: [status: String.to_existing_atom(status)]],
           authorize?: false
         ) do
      {:ok, orders} -> orders
      _ -> []
    end
  end
end
