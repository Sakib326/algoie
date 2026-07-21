defmodule Algoie.AI.Tools.QuerySalesReports do
  @moduledoc "Store-scoped sales analytics for the assistant."

  @behaviour Algoie.AI.Tool

  import Ash.Query

  alias Algoie.Orders.{Order, OrderLineItem}

  @periods %{"7" => 7, "30" => 30, "90" => 90, "365" => 365, "all" => nil}
  @revenue_statuses [:confirmed, :fulfilled]

  @impl true
  def definition do
    %{
      id: "query_sales_reports",
      version: 1,
      description:
        "Query sales analytics for the current store, including revenue, order counts, status breakdown, and best-selling products from order line items. Use this for best sellers, top products, sales performance, revenue, and sales summaries.",
      risk: :read_only,
      permissions: ["reports.view"],
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "period" => %{
            "type" => "string",
            "enum" => ["7", "30", "90", "365", "all"],
            "description" => "Reporting period in days, or all. Defaults to 30."
          },
          "rank_by" => %{
            "type" => "string",
            "enum" => ["quantity", "revenue"],
            "description" => "How to rank best-selling products. Defaults to quantity."
          },
          "limit" => %{
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 25,
            "description" => "Maximum top products to return. Defaults to 10."
          }
        }
      },
      handler: &handle/2
    }
  end

  def handle(args, context) do
    period = normalize_period(Map.get(args, "period"))
    days = Map.fetch!(@periods, period)
    rank_by = normalize_rank(Map.get(args, "rank_by"))
    limit = normalize_limit(Map.get(args, "limit"))

    with {:ok, orders} <- read_orders(context),
         {:ok, line_items} <- read_line_items(context) do
      current_orders = filter_period(orders, days)
      revenue_orders = Enum.filter(current_orders, &(&1.status in @revenue_statuses))
      revenue = sum(revenue_orders, & &1.total_amount)

      {:ok,
       %{
         period: period_label(period),
         generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
         revenue: Decimal.to_string(revenue, :normal),
         orders: length(current_orders),
         revenue_orders: length(revenue_orders),
         average_order_value:
           revenue |> average(length(revenue_orders)) |> Decimal.to_string(:normal),
         unique_customers:
           current_orders |> Enum.map(& &1.customer_id) |> Enum.uniq() |> length(),
         status_breakdown: status_breakdown(current_orders),
         ranked_by: rank_by,
         top_products: top_products(line_items, revenue_orders, rank_by, limit)
       }}
    end
  end

  defp read_orders(context) do
    Order
    |> filter(store_id == ^context.store_id)
    |> Ash.read(ash_opts(context, page: false))
  end

  defp read_line_items(context) do
    OrderLineItem
    |> filter(order.store_id == ^context.store_id)
    |> Ash.read(ash_opts(context))
  end

  defp ash_opts(context, extra \\ []) do
    Keyword.merge(
      [
        actor: context.actor,
        tenant: context.tenant,
        context: %{store_id: context.store_id, tenant: context.tenant},
        authorize?: false
      ],
      extra
    )
  end

  defp filter_period(orders, nil), do: orders

  defp filter_period(orders, days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    Enum.filter(orders, &(DateTime.compare(&1.inserted_at, cutoff) != :lt))
  end

  defp status_breakdown(orders) do
    orders
    |> Enum.frequencies_by(&to_string(&1.status))
    |> Map.new(fn {status, count} -> {status, count} end)
  end

  defp top_products(line_items, orders, rank_by, limit) do
    order_ids = MapSet.new(orders, & &1.id)

    line_items
    |> Enum.filter(&MapSet.member?(order_ids, &1.order_id))
    |> Enum.group_by(& &1.product_name)
    |> Enum.map(fn {product, items} ->
      %{
        product: product,
        variants: items |> Enum.map(& &1.variant_name) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
        skus: items |> Enum.map(& &1.sku) |> Enum.uniq(),
        quantity_sold: Enum.sum(Enum.map(items, & &1.quantity)),
        revenue:
          items
          |> Enum.reduce(Decimal.new(0), fn item, total ->
            Decimal.add(total, Decimal.mult(item.unit_price, item.quantity))
          end)
          |> Decimal.to_string(:normal)
      }
    end)
    |> Enum.sort(&ranked_before?(&1, &2, rank_by))
    |> Enum.take(limit)
  end

  defp ranked_before?(left, right, "revenue"),
    do: Decimal.compare(Decimal.new(left.revenue), Decimal.new(right.revenue)) == :gt

  defp ranked_before?(left, right, _rank_by), do: left.quantity_sold > right.quantity_sold

  defp sum(records, getter),
    do: Enum.reduce(records, Decimal.new(0), &Decimal.add(getter.(&1), &2))

  defp average(_total, 0), do: Decimal.new(0)
  defp average(total, count), do: Decimal.div(total, Decimal.new(count))

  defp period_label("all"), do: "all time"
  defp period_label(period), do: "last #{period} days"

  defp normalize_period(period) when is_map_key(@periods, period), do: period
  defp normalize_period(_period), do: "30"

  defp normalize_rank(rank) when rank in ["quantity", "revenue"], do: rank
  defp normalize_rank(_rank), do: "quantity"

  defp normalize_limit(limit) when is_integer(limit), do: limit |> min(25) |> max(1)
  defp normalize_limit(_limit), do: 10
end
