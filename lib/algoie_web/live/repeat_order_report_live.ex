defmodule AlgoieWeb.RepeatOrderReportLive do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.Order

  @periods %{"7" => 7, "30" => 30, "90" => 90, "365" => 365, "all" => nil}
  @revenue_statuses [:confirmed, :fulfilled]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Repeat orders")
     |> assign(:active, :repeat_orders)
     |> assign(:period, "90")
     |> load_report()}
  end

  @impl true
  def handle_event("period", %{"period" => period}, socket) when is_map_key(@periods, period) do
    {:noreply, socket |> assign(:period, period) |> load_report()}
  end

  def handle_event("period", _params, socket), do: {:noreply, socket}

  defp load_report(socket) do
    orders =
      socket
      |> read_orders()
      |> filter_period(@periods[socket.assigns.period])
      |> Enum.reject(&(&1.status == :cancelled))

    customers =
      orders
      |> Enum.group_by(& &1.customer_id)
      |> Enum.map(fn {customer_id, customer_orders} ->
        customer_summary(customer_id, customer_orders)
      end)

    repeat_customers = Enum.filter(customers, &(&1.order_count >= 2))

    repeat_orders =
      repeat_customers
      |> Enum.flat_map(& &1.repeat_orders)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    assign(socket,
      report: %{
        customers: length(customers),
        repeat_customers: length(repeat_customers),
        repeat_rate: percentage(length(repeat_customers), length(customers)),
        repeat_order_count: length(repeat_orders),
        repeat_revenue: repeat_customers |> Enum.map(& &1.repeat_revenue) |> decimal_sum(),
        average_frequency: average_frequency(repeat_customers),
        customer_rows: Enum.sort_by(repeat_customers, & &1.total_revenue, {:desc, Decimal}),
        recent_repeat_orders: Enum.take(repeat_orders, 10)
      }
    )
  end

  defp read_orders(socket) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    case Ash.read(Order, opts) do
      {:ok, orders} -> orders
      _ -> []
    end
  end

  defp filter_period(orders, nil), do: orders

  defp filter_period(orders, days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    Enum.filter(orders, &(DateTime.compare(&1.inserted_at, cutoff) != :lt))
  end

  defp customer_summary(customer_id, orders) do
    orders = Enum.sort_by(orders, & &1.inserted_at, DateTime)
    [first_order | repeat_orders] = orders
    revenue_orders = Enum.filter(orders, &(&1.status in @revenue_statuses))
    repeat_revenue_orders = Enum.filter(repeat_orders, &(&1.status in @revenue_statuses))
    last_order = List.last(orders)

    %{
      customer_id: customer_id,
      name: last_order.customer_name,
      email: last_order.customer_email,
      order_count: length(orders),
      first_order_at: first_order.inserted_at,
      last_order_at: last_order.inserted_at,
      total_revenue: revenue_orders |> Enum.map(& &1.total_amount) |> decimal_sum(),
      repeat_revenue: repeat_revenue_orders |> Enum.map(& &1.total_amount) |> decimal_sum(),
      repeat_orders: repeat_orders
    }
  end

  defp decimal_sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
  defp percentage(_part, 0), do: 0
  defp percentage(part, total), do: round(part / total * 100)
  defp average_frequency([]), do: 0.0

  defp average_frequency(customers) do
    customers
    |> Enum.map(& &1.order_count)
    |> then(&(Enum.sum(&1) / length(&1)))
    |> Float.round(1)
  end

  defp money(amount), do: "৳" <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))
  defp short_date(date), do: Calendar.strftime(date, "%d %b %Y")
  defp short_time(date), do: Calendar.strftime(date, "%d %b, %H:%M")

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp status_tone(:pending), do: "warning"
  defp status_tone(:pre_order), do: "info"
  defp status_tone(:confirmed), do: "primary"
  defp status_tone(:fulfilled), do: "success"
  defp status_tone(_), do: "neutral"
end
