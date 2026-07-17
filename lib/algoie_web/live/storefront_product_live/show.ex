defmodule AlgoieWeb.StorefrontProductLive.Show do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  alias Algoie.Products.{Product, Variant, ProductImage}

  require Ash.Query

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    tenant = socket.assigns.tenant
    store_id = socket.assigns.store_id

    product =
      Product
      |> Ash.Query.filter(slug == ^slug and store_id == ^store_id and status == :active)
      |> Ash.Query.limit(1)
      |> Ash.read!(tenant: tenant, authorize?: false)
      |> List.first()

    {variants, product_images, variant_images} =
      if product do
        variants =
          Variant
          |> Ash.Query.filter(product_id == ^product.id)
          |> Ash.Query.sort(:position)
          |> Ash.read!(tenant: tenant, authorize?: false)

        product_images =
          ProductImage
          |> Ash.Query.filter(product_id == ^product.id and is_nil(variant_id))
          |> Ash.Query.sort(:position)
          |> Ash.Query.load(media_asset: :url)
          |> Ash.read!(tenant: tenant, authorize?: false)

        variant_images =
          ProductImage
          |> Ash.Query.filter(product_id == ^product.id and not is_nil(variant_id))
          |> Ash.Query.sort(:position)
          |> Ash.Query.load(media_asset: :url)
          |> Ash.read!(tenant: tenant, authorize?: false)

        {variants, product_images, variant_images}
      else
        {[], [], []}
      end

    cover_url =
      case product_images do
        [%{media_asset: %{url: url}} | _] -> url
        _ -> nil
      end

    image_urls =
      product_images
      |> Enum.map(& &1.media_asset.url)

    images_by_variant =
      variant_images
      |> Enum.group_by(& &1.variant_id)
      |> Map.new(fn {vid, imgs} ->
        {vid, Enum.map(imgs, & &1.media_asset.url)}
      end)

    {:ok,
     socket
     |> assign(:page_title, if(product, do: product.name, else: "Product"))
     |> assign(:product, product)
     |> assign(:variants, variants)
     |> assign(:cover_url, cover_url)
     |> assign(:image_urls, image_urls)
     |> assign(:images_by_variant, images_by_variant)}
  end
end
