tenant = "tenant_82c28c95-e068-4d07-ae9d-d74c0d32321d"
product_id = "afcb1aba-7328-4163-8b24-bad6f965a9fd"
store_id = "59e2eeea-f1f2-4cf0-95c6-777445fa0cc3"

require Ash.Query

actor = 
  Algoie.Accounts.User
  |> Ash.Query.filter(id == "699c3162-862d-4edf-aae6-eeb1dec617a6")
  |> Ash.read_one!(authorize?: false)

opts = [tenant: tenant, actor: actor, context: %{store_id: store_id, tenant: tenant}]

query =
  Algoie.Products.ProductImage
  |> Ash.Query.filter(product_id == ^product_id and is_nil(variant_id))
  |> Ash.Query.sort(:position)
  |> Ash.Query.load(:media_asset)

case Ash.read(query, opts) do
  {:ok, images} ->
    urls = Enum.map(images, fn img -> 
      if img.media_asset do
        img.media_asset.url
      else
        "NO MEDIA ASSET LOADED"
      end
    end)
    IO.inspect(urls, label: "SUCCESS")
  err -> IO.inspect(err, label: "ERROR")
end
