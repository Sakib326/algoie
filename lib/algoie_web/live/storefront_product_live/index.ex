defmodule AlgoieWeb.StorefrontProductLive.Index do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  alias Algoie.Products.{Product, Variant, ProductImage}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Products")
     |> assign(:page, 1)
     |> assign(:products_page, nil)
     |> assign(:products, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {p, _} when p > 0 -> p
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> load_products()}
  end

  defp load_products(socket) do
    tenant = socket.assigns.tenant
    store_id = socket.assigns.store_id
    limit = 12
    offset = (socket.assigns.page - 1) * limit

    page_result =
      Product
      |> Ash.Query.filter(status == :active and store_id == ^store_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(tenant: tenant, authorize?: false, page: [offset: offset, count: true])

    products = page_result.results
    product_ids = Enum.map(products, & &1.id)

    variants =
      if product_ids != [] do
        Variant
        |> Ash.Query.filter(product_id in ^product_ids)
        |> Ash.read!(tenant: tenant, authorize?: false)
      else
        []
      end

    product_images =
      if product_ids != [] do
        ProductImage
        |> Ash.Query.filter(product_id in ^product_ids and is_nil(variant_id))
        |> Ash.Query.sort(:position)
        |> Ash.Query.load(media_asset: :url)
        |> Ash.read!(tenant: tenant, authorize?: false)
      else
        []
      end

    images_by_product =
      product_images
      |> Enum.group_by(& &1.product_id)

    variants_by_product =
      variants
      |> Enum.group_by(& &1.product_id)
      |> Map.new(fn {pid, vs} ->
        prices = Enum.map(vs, & &1.price) |> Enum.reject(&is_nil/1)
        min_price = if prices != [], do: Enum.min(prices, Decimal, &Decimal.compare/2), else: nil
        has_stock = Enum.any?(vs, &(&1.stock > 0))
        {pid, %{min_price: min_price, in_stock: has_stock, variant_count: length(vs)}}
      end)

    enriched =
      Enum.map(products, fn p ->
        price_info =
          variants_by_product[p.id] || %{min_price: nil, in_stock: false, variant_count: 0}

        images = images_by_product[p.id] || []

        cover_url =
          case images do
            [%{media_asset: %{url: url}} | _] -> url
            _ -> nil
          end

        Map.merge(p, %{
          min_price: price_info.min_price,
          in_stock: price_info.in_stock,
          variant_count: price_info.variant_count,
          cover_url: cover_url
        })
      end)

    socket
    |> assign(:products_page, page_result)
    |> assign(:products, enriched)
  end
end
