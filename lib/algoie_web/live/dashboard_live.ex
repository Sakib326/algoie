defmodule AlgoieWeb.DashboardLive do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Product
  alias Algoie.Orders.Order
  alias Algoie.Customers.Customer

  @impl true
  def mount(_params, _session, socket) do
    products = safe_read(socket, Product)
    orders = safe_read(socket, Order)
    customers = safe_read(socket, Customer)
    customer_map = Map.new(customers, &{&1.id, &1.name})

    revenue =
      orders
      |> Enum.filter(&(&1.status in [:confirmed, :fulfilled]))
      |> Enum.reduce(Decimal.new(0), fn order, acc -> Decimal.add(acc, order.total_amount) end)

    recent_orders =
      orders
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(6)

    {:ok,
     socket
     |> assign(:page_title, "Overview")
     |> assign(:active, :overview)
     |> assign(:product_count, length(products))
     |> assign(:active_product_count, Enum.count(products, &(&1.status == :active)))
     |> assign(:order_count, length(orders))
     |> assign(:pending_order_count, Enum.count(orders, &(&1.status == :pending)))
     |> assign(:customer_count, length(customers))
     |> assign(:customer_map, customer_map)
     |> assign(:revenue, revenue)
     |> assign(:recent_orders, recent_orders)}
  end

  defp safe_read(socket, resource, extra \\ []) do
    opts = AlgoieWeb.Scope.opts(socket, extra) |> Keyword.put(:page, false)

    case Ash.read(resource, opts) do
      {:ok, records} -> records
      _ -> []
    end
  end

  defp format_money(%Decimal{} = amount) do
    "৳" <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))
  end

  defp format_money(_), do: "৳0.00"

  defp status_tone(:pending), do: "warning"
  defp status_tone(:pre_order), do: "info"
  defp status_tone(:confirmed), do: "primary"
  defp status_tone(:fulfilled), do: "success"
  defp status_tone(:cancelled), do: "error"
  defp status_tone(_), do: "neutral"

  defp humanize(status), do: status |> to_string() |> String.replace("_", " ")

  defp short_id(id), do: id |> to_string() |> String.slice(0, 8)
end
