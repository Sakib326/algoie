defmodule Algoie.AI.Tools.ListProducts do
  @moduledoc "Lists products in the current store with optional filters."

  alias Algoie.Products.Product
  import Ash.Query

  def definition do
    %{
      id: "list_products",
      version: 1,
      description: "List products in the store. Returns name, status, SKU, price, and stock for each.",
      risk: :read_only,
      permissions: ["catalog.view"],
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "status" => %{
            "type" => "string",
            "enum" => ["draft", "active", "archived"],
            "description" => "Filter by product status"
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
      Product
      |> filter(store_id == ^context.store_id)
      |> then(fn q -> if status, do: filter(q, status == ^status), else: q end)
      |> limit(limit)
      |> load([:brand, :category, variants: []])

    case Ash.read(query,
           actor: context.actor,
           tenant: context.tenant,
           authorize?: false
         ) do
      {:ok, products} ->
        {:ok,
         %{
           products:
             Enum.map(products, fn p ->
               %{
                 id: p.id,
                 name: p.name,
                 status: p.status,
                 description: p.description,
                 variants:
                   Enum.map(p.variants || [], fn v ->
                     %{sku: v.sku, price: Decimal.to_string(v.price), stock: v.stock}
                   end)
               }
             end),
           count: length(products)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
