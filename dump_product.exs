import Ash.Query

tenant = "tenant_82c28c95-e068-4d07-ae9d-d74c0d32321d"
product_id = "afcb1aba-7328-4163-8b24-bad6f965a9fd"

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

# Use inspect since Ash models often have #Ash.NotLoaded structs that break Jason.encode!
IO.puts(inspect(product, pretty: true, limit: :infinity, printable_limit: :infinity, structs: false))
