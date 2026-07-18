defmodule AlgoieWeb.ProductLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.{Product, ProductImage}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    brands = list_related(socket, Algoie.Products.Brand)
    categories = list_related(socket, Algoie.Products.Category)

    {:ok,
     socket
     |> assign(:active, :products)
     |> assign(:brands, brands)
     |> assign(:categories, categories)
     |> assign(:brand_map, Map.new(brands, &{&1.id, &1.name}))
     |> assign(:category_map, Map.new(categories, &{&1.id, &1.name}))
     |> assign(:search, "")
     |> assign(:filter_category, "")
     |> assign(:filter_brand, "")
     |> assign(:filter_status, "")
     |> assign(:filter_stock, "")
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

    socket =
      socket
      |> assign(:page, page)
      |> apply_action(socket.assigns.live_action, params)
      |> load_products()

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Products")
    |> assign(:product, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = get_product(socket, id)
    Ash.destroy!(product, AlgoieWeb.Scope.opts(socket))
    {:noreply, load_products(socket)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> load_products()}
  end

  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:filter_category, Map.get(params, "category", ""))
     |> assign(:filter_brand, Map.get(params, "brand", ""))
     |> assign(:filter_status, Map.get(params, "status", ""))
     |> assign(:filter_stock, Map.get(params, "stock", ""))
     |> assign(:page, 1)
     |> load_products()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:search, "")
     |> assign(:filter_category, "")
     |> assign(:filter_brand, "")
     |> assign(:filter_status, "")
     |> assign(:filter_stock, "")
     |> assign(:page, 1)
     |> load_products()}
  end

  defp load_products(socket) do
    opts = AlgoieWeb.Scope.opts(socket)

    query =
      Product
      |> Ash.Query.new()

    query =
      if socket.assigns.search != "" do
        search = "%#{socket.assigns.search}%"

        query
        |> Ash.Query.filter(
          ilike(name, ^search) or
            fragment(
              "EXISTS (SELECT 1 FROM variants WHERE variants.product_id = products.id AND (variants.sku ILIKE ? OR variants.barcode ILIKE ?))",
              ^search,
              ^search
            )
        )
      else
        query
      end

    query =
      if socket.assigns.filter_category != "" do
        Ash.Query.filter(query, category_id == ^socket.assigns.filter_category)
      else
        query
      end

    query =
      if socket.assigns.filter_brand != "" do
        Ash.Query.filter(query, brand_id == ^socket.assigns.filter_brand)
      else
        query
      end

    query =
      if socket.assigns.filter_status != "" do
        status = String.to_existing_atom(socket.assigns.filter_status)
        Ash.Query.filter(query, status == ^status)
      else
        query
      end

    query =
      case socket.assigns.filter_stock do
        "in_stock" ->
          Ash.Query.filter(
            query,
            fragment(
              "EXISTS (SELECT 1 FROM variants v WHERE v.product_id = products.id AND (v.\"track_inventory?\" = false OR v.stock > 0))"
            )
          )

        "out_of_stock" ->
          Ash.Query.filter(
            query,
            fragment(
              "NOT EXISTS (SELECT 1 FROM variants v WHERE v.product_id = products.id AND (v.\"track_inventory?\" = false OR v.stock > 0))"
            )
          )

        "low_stock" ->
          Ash.Query.filter(
            query,
            fragment(
              "EXISTS (SELECT 1 FROM variants v WHERE v.product_id = products.id AND v.\"track_inventory?\" = true AND v.stock > 0 AND v.stock <= v.low_stock_threshold)"
            )
          )

        _ ->
          query
      end

    query = Ash.Query.sort(query, inserted_at: :desc)
    
    limit = 12
    offset = (socket.assigns.page - 1) * limit
    
    opts = Keyword.put(opts, :page, offset: offset, count: true)

    case Ash.read(query, opts) do
      {:ok, page_result} ->
        products = attach_cover_urls(page_result.results, opts)
        
        socket
        |> assign(:products, products)
        |> assign(:products_page, page_result)

      _ ->
        socket
        |> assign(:products, [])
        |> assign(:products_page, nil)
    end
  end

  defp attach_cover_urls([], _opts), do: []

  defp attach_cover_urls(products, opts) do
    product_ids = Enum.map(products, & &1.id)
    opts = Keyword.put(opts, :page, false)

    product_images =
      ProductImage
      |> Ash.Query.filter(product_id in ^product_ids and is_nil(variant_id))
      |> Ash.Query.sort(:position)
      |> Ash.Query.load(media_asset: [:url])
      |> Ash.read(opts)
      |> case do
        {:ok, images} -> images
        _ -> []
      end

    covers_by_product =
      product_images
      |> Enum.group_by(& &1.product_id)
      |> Map.new(fn {product_id, images} ->
        cover_url =
          case images do
            [%{media_asset: %{url: url}} | _] when is_binary(url) and url != "" -> url
            _ -> nil
          end

        {product_id, cover_url}
      end)

    Enum.map(products, fn product ->
      Map.put(product, :cover_url, Map.get(covers_by_product, product.id))
    end)
  end

  defp list_related(socket, resource) do
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, false)
    case Ash.read(resource, opts) do
      {:ok, records} -> records
      _ -> []
    end
  end

  defp get_product(socket, id) do
    case Ash.get(Product, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, product} -> product
      _ -> nil
    end
  end

  defp status_tone(:active), do: "success"
  defp status_tone(:draft), do: "warning"
  defp status_tone(:archived), do: "neutral"
  defp status_tone(_), do: "neutral"
end
