defmodule AlgoieWeb.SalesReportLive do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.{Order, OrderLineItem}

  @periods %{"7" => 7, "30" => 30, "90" => 90, "365" => 365, "all" => nil}
  @revenue_statuses [:confirmed, :fulfilled]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sales report")
     |> assign(:active, :sales_report)
     |> assign(:period, "30")
     |> assign(:detail_search, "")
     |> assign(:detail_status, "all")
     |> assign(:detail_page, 1)
     |> load_report()}
  end

  @impl true
  def handle_event("period", %{"period" => period}, socket) when is_map_key(@periods, period) do
    {:noreply, socket |> assign(:period, period) |> assign(:detail_page, 1) |> load_report()}
  end

  def handle_event("period", _params, socket), do: {:noreply, socket}

  def handle_event("filter-orders", %{"orders" => params}, socket) do
    {:noreply,
     socket
     |> assign(:detail_search, String.trim(params["search"] || ""))
     |> assign(:detail_status, params["status"] || "all")
     |> assign(:detail_page, 1)
     |> apply_detail_view()}
  end

  def handle_event("detail-page", %{"page" => page}, socket) do
    page = page |> String.to_integer() |> max(1) |> min(socket.assigns.detail_total_pages)
    {:noreply, socket |> assign(:detail_page, page) |> apply_detail_view()}
  end

  defp load_report(socket) do
    orders = read_all(socket, Order)
    line_items = read_all(socket, OrderLineItem)
    days = @periods[socket.assigns.period]
    now = DateTime.utc_now()
    current = filter_period(orders, days, now)
    previous = previous_period(orders, days, now)
    revenue_orders = Enum.filter(current, &(&1.status in @revenue_statuses))
    previous_revenue_orders = Enum.filter(previous, &(&1.status in @revenue_statuses))

    revenue = sum(revenue_orders, & &1.total_amount)
    previous_revenue = sum(previous_revenue_orders, & &1.total_amount)
    paid_orders = Enum.filter(current, &(&1.payment_status == :paid))
    refunded = current |> Enum.filter(&(&1.payment_status == :refunded)) |> sum(& &1.total_amount)

    socket
    |> assign(:detail_source, Enum.sort_by(current, & &1.inserted_at, {:desc, DateTime}))
    |> assign(:report, %{
      revenue: revenue,
      revenue_change: percent_change(revenue, previous_revenue),
      orders: length(current),
      completed_orders: length(revenue_orders),
      average_order: average(revenue, length(revenue_orders)),
      paid_rate: ratio(length(paid_orders), length(current)),
      refunded: refunded,
      customers: current |> Enum.map(& &1.customer_id) |> Enum.uniq() |> length(),
      trend: trend(revenue_orders, days, now),
      statuses: status_breakdown(current),
      top_products: top_products(line_items, revenue_orders),
      recent_orders: current |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime}) |> Enum.take(8)
    })
    |> apply_detail_view()
  end

  defp apply_detail_view(socket) do
    search = String.downcase(socket.assigns.detail_search)
    status = socket.assigns.detail_status

    filtered =
      Enum.filter(socket.assigns.detail_source, fn order ->
        status_match? = status == "all" or to_string(order.status) == status

        searchable =
          [order.order_number, order.customer_name, order.customer_email]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")
          |> String.downcase()

        status_match? and (search == "" or String.contains?(searchable, search))
      end)

    page_size = 12
    total_pages = max(1, ceil(length(filtered) / page_size))
    page = min(socket.assigns.detail_page, total_pages)

    assign(socket,
      detail_orders: Enum.slice(filtered, (page - 1) * page_size, page_size),
      detail_count: length(filtered),
      detail_page: page,
      detail_total_pages: total_pages,
      detail_form:
        to_form(%{"search" => socket.assigns.detail_search, "status" => status}, as: :orders)
    )
  end

  defp read_all(socket, resource) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    case Ash.read(resource, opts) do
      {:ok, records} -> records
      _ -> []
    end
  end

  defp filter_period(orders, nil, _now), do: orders

  defp filter_period(orders, days, now) do
    cutoff = DateTime.add(now, -days, :day)
    Enum.filter(orders, &(DateTime.compare(&1.inserted_at, cutoff) != :lt))
  end

  defp previous_period(_orders, nil, _now), do: []

  defp previous_period(orders, days, now) do
    current_cutoff = DateTime.add(now, -days, :day)
    previous_cutoff = DateTime.add(now, -(days * 2), :day)

    Enum.filter(orders, fn order ->
      DateTime.compare(order.inserted_at, previous_cutoff) != :lt and
        DateTime.compare(order.inserted_at, current_cutoff) == :lt
    end)
  end

  defp trend(orders, days, now) do
    bucket_days = trend_days(days)
    revenue_by_date = Enum.group_by(orders, &DateTime.to_date(&1.inserted_at))

    for offset <- (bucket_days - 1)..0//-1 do
      date = now |> DateTime.add(-offset, :day) |> DateTime.to_date()
      amount = revenue_by_date |> Map.get(date, []) |> sum(& &1.total_amount)
      %{date: date, amount: amount}
    end
  end

  defp trend_days(nil), do: 30
  defp trend_days(days), do: min(days, 30)

  defp status_breakdown(orders) do
    for status <- [:pending, :pre_order, :confirmed, :fulfilled, :cancelled] do
      %{status: status, count: Enum.count(orders, &(&1.status == status))}
    end
  end

  defp top_products(line_items, orders) do
    order_ids = MapSet.new(orders, & &1.id)

    line_items
    |> Enum.filter(&MapSet.member?(order_ids, &1.order_id))
    |> Enum.group_by(&{&1.product_name, &1.variant_name})
    |> Enum.map(fn {{product, variant}, items} ->
      %{
        product: product,
        variant: variant,
        quantity: Enum.sum(Enum.map(items, & &1.quantity)),
        revenue:
          Enum.reduce(items, Decimal.new(0), fn item, total ->
            Decimal.add(total, Decimal.mult(item.unit_price, item.quantity))
          end)
      }
    end)
    |> Enum.sort_by(& &1.revenue, {:desc, Decimal})
    |> Enum.take(6)
  end

  defp sum(records, getter),
    do: Enum.reduce(records, Decimal.new(0), &Decimal.add(getter.(&1), &2))

  defp average(_total, 0), do: Decimal.new(0)
  defp average(total, count), do: Decimal.div(total, Decimal.new(count))
  defp ratio(_part, 0), do: 0
  defp ratio(part, total), do: round(part / total * 100)

  defp percent_change(current, previous) do
    if Decimal.equal?(previous, 0) do
      nil
    else
      current
      |> Decimal.sub(previous)
      |> Decimal.div(previous)
      |> Decimal.mult(100)
      |> Decimal.round(1)
      |> Decimal.to_float()
    end
  end

  defp max_trend(trend) do
    Enum.reduce(trend, Decimal.new(0), &Decimal.max(&1.amount, &2))
  end

  defp bar_height(amount, maximum) do
    if Decimal.equal?(maximum, 0),
      do: 4,
      else: max(4, round(Decimal.to_float(Decimal.div(amount, maximum)) * 100))
  end

  defp money(amount), do: "৳" <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp short_date(date), do: Calendar.strftime(date, "%d %b, %H:%M")
  defp status_tone(:pending), do: "warning"
  defp status_tone(:pre_order), do: "info"
  defp status_tone(:confirmed), do: "primary"
  defp status_tone(:fulfilled), do: "success"
  defp status_tone(:cancelled), do: "error"
end
