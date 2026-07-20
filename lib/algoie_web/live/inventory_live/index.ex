defmodule AlgoieWeb.InventoryLive.Index do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Products.{Product, Variant}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :inventory)
     |> assign(:page_title, "Inventory")
     |> assign(:filter, "all")
     |> assign(:search, "")
     |> assign(:page, 1)
     |> load_inventory()}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket),
    do: {:noreply, socket |> assign(:filter, status) |> assign(:page, 1) |> load_inventory()}

  def handle_event("search", %{"search" => search}, socket),
    do:
      {:noreply,
       socket |> assign(:search, String.trim(search)) |> assign(:page, 1) |> load_inventory()}

  def handle_event("page", %{"page" => page}, socket),
    do: {:noreply, socket |> assign(:page, parse_page(page)) |> load_inventory()}

  def handle_event("set_stock", %{"variant_id" => id, "stock" => stock}, socket) do
    with {quantity, ""} when quantity >= 0 <- Integer.parse(stock),
         {:ok, variant} <- Ash.get(Variant, id, AlgoieWeb.Scope.opts(socket)),
         {:ok, _} <- Ash.update(variant, %{stock: quantity}, AlgoieWeb.Scope.opts(socket)) do
      {:noreply, socket |> put_flash(:info, "Stock updated") |> load_inventory()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a valid stock quantity")}
    end
  end

  defp load_inventory(socket) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    products =
      case Ash.read(Product |> Ash.Query.filter(store_id == ^socket.assigns.store_id), opts) do
        {:ok, rows} -> Map.new(rows, &{&1.id, &1})
        _ -> %{}
      end

    all_variants =
      case Ash.read(
             Variant
             |> Ash.Query.filter(store_id == ^socket.assigns.store_id)
             |> Ash.Query.sort(updated_at: :desc),
             opts
           ) do
        {:ok, rows} -> rows
        _ -> []
      end

    matching_variants =
      all_variants
      |> Enum.filter(&matches_filter?(&1, socket.assigns.filter))
      |> Enum.filter(&matches_search?(&1, products, socket.assigns.search))

    page_size = 15
    page_count = max(ceil(length(matching_variants) / page_size), 1)
    page = min(socket.assigns.page, page_count)
    variants = Enum.slice(matching_variants, (page - 1) * page_size, page_size)

    tracked = Enum.filter(all_variants, & &1.track_inventory?)
    total_units = Enum.sum(Enum.map(tracked, &Variant.available_stock/1))
    low = Enum.count(tracked, &(Variant.available_stock(&1) > 0 and Variant.low_stock?(&1)))
    out = Enum.count(tracked, &(Variant.available_stock(&1) == 0))

    stock_value =
      Enum.reduce(tracked, Decimal.new(0), fn variant, total ->
        Decimal.add(
          total,
          Decimal.mult(
            variant.cost_price || variant.price,
            Decimal.new(Variant.available_stock(variant))
          )
        )
      end)

    socket
    |> assign(:variants, variants)
    |> assign(:products_by_id, products)
    |> assign(:page, page)
    |> assign(:page_count, page_count)
    |> assign(:summary, %{
      variants: length(all_variants),
      units: total_units,
      low: low,
      out: out,
      untracked: Enum.count(all_variants, &(!&1.track_inventory?)),
      value: stock_value
    })
  end

  defp matches_filter?(_variant, "all"), do: true
  defp matches_filter?(%{track_inventory?: false}, "untracked"), do: true

  defp matches_filter?(variant, "in_stock"),
    do:
      variant.track_inventory? and Variant.available_stock(variant) > variant.low_stock_threshold

  defp matches_filter?(variant, "low"),
    do:
      variant.track_inventory? and Variant.available_stock(variant) > 0 and
        Variant.low_stock?(variant)

  defp matches_filter?(variant, "out"),
    do: variant.track_inventory? and Variant.available_stock(variant) == 0

  defp matches_filter?(_, _), do: false

  defp matches_search?(_variant, _products, ""), do: true

  defp matches_search?(variant, products, search) do
    product = products[variant.product_id]
    haystack = "#{variant.sku} #{variant.barcode} #{product && product.name}" |> String.downcase()
    String.contains?(haystack, String.downcase(search))
  end

  defp product_name(products, variant) do
    case products[variant.product_id] do
      nil -> "Unknown product"
      product -> product.name
    end
  end

  defp option_label(options) when map_size(options) == 0, do: "Default variant"

  defp option_label(options),
    do: Enum.map_join(options, " / ", fn {key, value} -> "#{key}: #{value}" end)

  defp format_money(amount), do: "৳" <> Decimal.to_string(Decimal.round(amount, 2), :normal)

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
