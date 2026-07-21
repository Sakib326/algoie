defmodule Algoie.AI.Tools.ListOrders do
  @moduledoc "Lists recent orders in the current store."

  alias Algoie.Orders.Order
  import Ash.Query

  def definition do
    %{
      id: "list_orders",
      version: 1,
      description: "List recent orders. Returns order number, status, total, and date.",
      risk: :read_only,
      permissions: ["orders.view"],
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "status" => %{
            "type" => "string",
            "enum" => ["pending", "confirmed", "fulfilled", "cancelled"],
            "description" => "Filter by order status"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Max results (default 10, max 25)",
            "minimum" => 1,
            "maximum" => 25
          }
        }
      },
      handler: &handle/2
    }
  end

  def handle(args, context) do
    status = Map.get(args, "status")
    limit = args |> Map.get("limit", 10) |> min(25)

    query =
      Order
      |> filter(store_id == ^context.store_id)
      |> then(fn q -> if status, do: filter(q, status == ^status), else: q end)
      |> sort(inserted_at: :desc)
      |> limit(limit)

    case Ash.read(query,
           actor: context.actor,
           tenant: context.tenant,
           authorize?: false
         ) do
      {:ok, orders} ->
        {:ok,
         %{
           orders:
             Enum.map(orders, fn o ->
               %{
                 id: o.id,
                 order_number: o.order_number,
                 status: o.status,
                 total: Decimal.to_string(o.total_amount),
                 date: DateTime.to_iso8601(o.inserted_at)
               }
             end),
           count: length(orders)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
