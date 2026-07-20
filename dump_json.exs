import Ash.Query

tenant = "tenant_82c28c95-e068-4d07-ae9d-d74c0d32321d"
product_id = "afcb1aba-7328-4163-8b24-bad6f965a9fd"

defmodule Cleaner do
  def clean(list) when is_list(list), do: Enum.map(list, &clean/1)
  def clean(%Decimal{} = d), do: Decimal.to_float(d)
  def clean(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def clean(%{__struct__: Ash.NotLoaded}), do: nil

  def clean(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([
      :__meta__,
      :__metadata__,
      :aggregates,
      :calculations,
      :__lateral_join_source__,
      :__order__
    ])
    |> clean()
  end

  def clean(%{} = map) do
    map
    |> Enum.reject(fn {_, v} -> match?(%{__struct__: Ash.NotLoaded}, v) end)
    |> Enum.into(%{}, fn {k, v} -> {k, clean(v)} end)
  end

  def clean(other), do: other
end

product =
  Algoie.Products.Product
  |> Ash.Query.filter(id == ^product_id)
  |> Ash.Query.load([
    :variants,
    :categories,
    :tags,
    product_images: [:media_asset],
    variants: [product_images: [:media_asset]]
  ])
  |> Ash.read_one!(tenant: tenant, authorize?: false)

cleaned = Cleaner.clean(product)

IO.puts(Jason.encode!(cleaned, pretty: true))
