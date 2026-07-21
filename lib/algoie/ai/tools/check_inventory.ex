defmodule Algoie.AI.Tools.CheckInventory do
  @moduledoc "Shows stock levels for product variants."

  alias Algoie.Products.Variant
  import Ash.Query

  def definition do
    %{
      id: "check_inventory",
      version: 1,
      description: "Check stock levels for product variants. Shows SKU, price, stock, and low-stock warnings.",
      risk: :read_only,
      permissions: ["inventory.view"],
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "low_stock_only" => %{
            "type" => "boolean",
            "description" => "If true, only show variants at or below their low stock threshold"
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
    limit = args |> Map.get("limit", 10) |> min(25)
    low_stock_only = Map.get(args, "low_stock_only", false)

    query =
      Variant
      |> filter(store_id == ^context.store_id)
      |> then(fn q ->
        if low_stock_only do
          filter(q, fragment("? <= ?", as(:stock), as(:low_stock_threshold)))
        else
          q
        end
      end)
      |> load([:product])
      |> limit(limit)

    case Ash.read(query,
           actor: context.actor,
           tenant: context.tenant,
           authorize?: false
         ) do
      {:ok, variants} ->
        {:ok,
         %{
           variants:
             Enum.map(variants, fn v ->
               warning =
                 if v.track_inventory? and v.stock <= v.low_stock_threshold,
                   do: "LOW STOCK",
                   else: nil

               %{
                 sku: v.sku,
                 product: if(v.product, do: v.product.name),
                 price: Decimal.to_string(v.price),
                 stock: v.stock,
                 low_stock_threshold: v.low_stock_threshold,
                 warning: warning
               }
             end),
           count: length(variants)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
