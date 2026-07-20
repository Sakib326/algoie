defmodule AlgoieWeb.OrderLive.Invoice do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Orders.{Order, OrderLineItem}
  alias Algoie.Stores.Store

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(:page_title, "Invoice") |> load_invoice(id)}
  end

  defp load_invoice(socket, id) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    with {:ok, order} <- Ash.get(Order, id, AlgoieWeb.Scope.opts(socket)),
         {:ok, store} <- Ash.get(Store, socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      line_items =
        case OrderLineItem
             |> Ash.Query.filter(order_id == ^order.id)
             |> Ash.Query.sort(inserted_at: :asc)
             |> Ash.read(opts) do
          {:ok, rows} -> rows
          _ -> []
        end

      socket |> assign(:order, order) |> assign(:store, store) |> assign(:line_items, line_items)
    else
      _ -> socket |> assign(:order, nil) |> assign(:store, nil) |> assign(:line_items, [])
    end
  end

  defp format_money(amount), do: "৳" <> Decimal.to_string(Decimal.round(amount, 2), :normal)
  defp invoice_number(store, order), do: "#{store.invoice_prefix}-#{order.order_number}"

  defp address_value(address, key) do
    Map.get(address || %{}, key) || Map.get(address || %{}, to_string(key))
  end

  defp invoice_address(address) do
    [:address_line1, :address_line2, :area, :city, :postal_code, :country]
    |> Enum.map(&address_value(address, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end
end
