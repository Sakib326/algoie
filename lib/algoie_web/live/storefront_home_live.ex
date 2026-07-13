defmodule AlgoieWeb.StorefrontHomeLive do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  alias Algoie.Products.{Product, Variant, Category, Brand, Collection, CollectionProduct}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.tenant
    store_id = socket.assigns.store_id

    {featured_products, categories, brands, collections} = load_homepage_data(tenant, store_id)

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:featured_products, featured_products)
     |> assign(:categories, categories)
     |> assign(:brands, brands)
     |> assign(:collections, collections)}
  end

  defp load_homepage_data(tenant, store_id) do
    # Active products with their lowest variant price
    products =
      Product
      |> Ash.Query.filter(status == :active and store_id == ^store_id)
      |> Ash.Query.limit(8)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(tenant: tenant, authorize?: false)

    product_ids = Enum.map(products, & &1.id)

    # Fetch variants for price display
    variants =
      if product_ids != [] do
        Variant
        |> Ash.Query.filter(product_id in ^product_ids)
        |> Ash.read!(tenant: tenant, authorize?: false)
      else
        []
      end

    # Group variants by product and find lowest price
    variants_by_product =
      variants
      |> Enum.group_by(& &1.product_id)
      |> Map.new(fn {pid, vs} ->
        prices = Enum.map(vs, & &1.price) |> Enum.reject(&is_nil/1)
        min_price = if prices != [], do: Enum.min(prices, Decimal, &Decimal.compare/2), else: nil
        has_stock = Enum.any?(vs, &(&1.stock > 0))
        {pid, %{min_price: min_price, has_stock: has_stock}}
      end)

    featured_products =
      Enum.map(products, fn p ->
        price_info = variants_by_product[p.id] || %{min_price: nil, has_stock: false}
        Map.merge(p, %{min_price: price_info.min_price, in_stock: price_info.has_stock})
      end)

    # Top-level categories
    categories =
      Category
      |> Ash.Query.filter(store_id == ^store_id and is_nil(parent_id))
      |> Ash.Query.sort(:name)
      |> Ash.read!(tenant: tenant, authorize?: false)

    # Brands
    brands =
      Brand
      |> Ash.Query.filter(store_id == ^store_id)
      |> Ash.Query.sort(:name)
      |> Ash.read!(tenant: tenant, authorize?: false)

    # Collections with product counts
    collections =
      Collection
      |> Ash.Query.filter(store_id == ^store_id)
      |> Ash.Query.sort(:name)
      |> Ash.read!(tenant: tenant, authorize?: false)

    collection_ids = Enum.map(collections, & &1.id)

    cp_counts =
      if collection_ids != [] do
        CollectionProduct
        |> Ash.Query.filter(collection_id in ^collection_ids)
        |> Ash.read!(tenant: tenant, authorize?: false)
        |> Enum.group_by(& &1.collection_id)
        |> Map.new(fn {cid, cps} -> {cid, length(cps)} end)
      else
        %{}
      end

    collections =
      Enum.map(collections, fn c ->
        Map.put(c, :product_count, Map.get(cp_counts, c.id, 0))
      end)

    {featured_products, categories, brands, collections}
  end
end
