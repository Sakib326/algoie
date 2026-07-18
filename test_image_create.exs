require Logger

opts = [
  tenant: "tenant_82c28c95-e068-4d07-ae9d-d74c0d32321d",
  context: %{store_id: "59e2eeea-f1f2-4cf0-95c6-777445fa0cc3"}
]

product_id =
  case Ash.read_first(Algoie.Products.Product, opts) do
    {:ok, %{id: id}} -> id
    _ -> nil
  end

media_asset_id =
  case Ash.read_first(Algoie.Media.MediaAsset, opts) do
    {:ok, %{id: id}} -> id
    _ -> nil
  end

if product_id && media_asset_id do
  IO.puts("Creating product image...")

  case Ash.create(
         Algoie.Products.ProductImage,
         %{product_id: product_id, media_asset_id: media_asset_id, position: 0},
         opts
       ) do
    {:ok, record} -> IO.puts("Success! ID: #{record.id}")
    {:error, error} -> IO.inspect(error, label: "Error")
  end
else
  IO.puts("Product or Media Asset not found")
end
