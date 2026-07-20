defmodule Algoie.Storefront.Cart do
  @moduledoc """
  Store-scoped cart helpers. Cart identifiers live in the signed browser session;
  prices, availability and product ownership are always reloaded from the tenant schema.
  """

  require Ash.Query

  alias Algoie.Products.{Product, Variant}

  def normalize(%{"store_id" => store_id, "items" => items}, store_id)
      when is_map(items),
      do: %{"store_id" => store_id, "items" => items}

  def normalize(_, store_id), do: %{"store_id" => store_id, "items" => %{}}

  def put(raw_cart, store_id, variant_id, quantity) do
    cart = normalize(raw_cart, to_string(store_id))
    items = cart["items"]

    items =
      if quantity > 0,
        do: Map.put(items, to_string(variant_id), min(quantity, 99)),
        else: Map.delete(items, to_string(variant_id))

    %{cart | "items" => items}
  end

  def remove(raw_cart, store_id, variant_id), do: put(raw_cart, store_id, variant_id, 0)

  def load(tenant, store_id, raw_cart) do
    cart = normalize(raw_cart, to_string(store_id))
    quantities = cart["items"]
    variant_ids = Map.keys(quantities)

    variants =
      if variant_ids == [] do
        []
      else
        Variant
        |> Ash.Query.filter(id in ^variant_ids and store_id == ^store_id)
        |> Ash.read!(tenant: tenant, authorize?: false, page: false)
      end

    products =
      variants
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()
      |> then(fn
        [] ->
          []

        ids ->
          Product
          |> Ash.Query.filter(id in ^ids and store_id == ^store_id and status == :active)
          |> Ash.read!(tenant: tenant, authorize?: false, page: false)
      end)
      |> Map.new(&{&1.id, &1})

    items =
      variants
      |> Enum.filter(&Map.has_key?(products, &1.product_id))
      |> Enum.map(fn variant ->
        requested = parse_quantity(quantities[to_string(variant.id)])

        available =
          if variant.track_inventory?,
            do: max(variant.stock - variant.reserved_quantity, 0),
            else: 99

        quantity = min(requested, available)

        %{
          variant: variant,
          product: Map.fetch!(products, variant.product_id),
          quantity: quantity,
          available: available,
          line_total: Decimal.mult(variant.price, Decimal.new(quantity))
        }
      end)
      |> Enum.filter(&(&1.quantity > 0))
      |> Enum.sort_by(& &1.product.name)

    subtotal = Enum.reduce(items, Decimal.new(0), &Decimal.add(&1.line_total, &2))
    %{items: items, subtotal: subtotal, count: Enum.sum(Enum.map(items, & &1.quantity))}
  end

  def parse_quantity(value) do
    case Integer.parse(to_string(value || "0")) do
      {quantity, ""} when quantity > 0 -> min(quantity, 99)
      _ -> 0
    end
  end
end
