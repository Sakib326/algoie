defmodule Algoie.Products.VariantGenerator do
  @moduledoc """
  Generates variant combinations from product attribute definitions.

  Takes a map of attribute definitions (e.g., %{"Color" => ["Red", "Blue"], "Size" => ["S", "M"]})
  and produces the cartesian product as a list of option_values maps.
  """

  @doc """
  Generates cartesian product of attribute values.
  Returns a list of maps, each representing one variant's option_values.
  """
  @spec generate(map()) :: [map()]
  def generate(attrs) when is_map(attrs) and map_size(attrs) == 0, do: []

  def generate(attrs) when is_map(attrs) do
    attrs
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {attr, values} -> Enum.map(values, &{attr, &1}) end)
    |> cartesian()
    |> Enum.map(&Map.new/1)
  end

  def generate(_), do: []

  @doc """
  Generates a SKU string from a product slug and option_values.
  """
  @spec generate_sku(String.t(), map()) :: String.t()
  def generate_sku(product_slug, option_values) when map_size(option_values) == 0 do
    product_slug
  end

  def generate_sku(product_slug, option_values) do
    suffix =
      option_values
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_k, v} -> Slug.slugify(to_string(v)) end)
      |> Enum.join("-")

    "#{product_slug}-#{suffix}"
  end

  # Cartesian product: given [[a,b], [c,d], [e,f]] -> [[a,c,e], [a,c,f], ...]
  defp cartesian([]), do: [[]]

  defp cartesian([head | rest]) do
    rest_cartesian = cartesian(rest)
    for item <- head, rest_item <- rest_cartesian, do: [item | rest_item]
  end
end
