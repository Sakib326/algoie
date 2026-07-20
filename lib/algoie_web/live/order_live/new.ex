defmodule AlgoieWeb.OrderLive.New do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Customers.{Coupon, Customer}
  alias Algoie.Orders.OrderWorkflow
  alias Algoie.Products.{Product, Variant}
  alias Algoie.Stores.DeliveryCharge

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:active, :orders)
      |> assign(:page_title, "Create order")
      |> assign(:submitting?, false)
      |> assign(:catalog_page, 1)
      |> assign(:catalog_search, "")
      |> load_reference_data()
      |> assign_form(%{})

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"order" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("catalog_page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {value, ""} when value > 0 -> value
        _ -> 1
      end

    {:noreply, socket |> assign(:catalog_page, page) |> assign_catalog()}
  end

  def handle_event("create", %{"order" => params}, socket) do
    items_params = Map.merge(current_items(socket), params["items"] || %{})

    with {:ok, items} <- line_items(items_params),
         {:ok, customer} <- customer_attrs(params),
         attrs <- %{
           store_id: socket.assigns.store_id,
           customer_id: customer[:customer_id],
           customer: customer[:customer],
           address: address_attrs(params),
           variant_quantities: items,
           coupon_code: params["coupon_code"],
           shipping_amount: params["shipping_amount"],
           delivery_charge_id: blank_to_nil(params["delivery_charge_id"]),
           delivery_method:
             selected_delivery_name(
               socket.assigns.delivery_rates,
               params["delivery_charge_id"]
             ),
           notes: params["notes"]
         },
         {:ok, order} <-
           OrderWorkflow.create_order(socket.assigns.tenant, attrs, socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, "Order #{order.order_number} created")
       |> push_navigate(to: ~p"/dashboard/orders/#{order.id}")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:submitting?, false)
         |> assign_form(params)
         |> put_flash(:error, error_message(reason))}
    end
  end

  defp load_reference_data(socket) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    customers =
      case Ash.read(Customer |> Ash.Query.sort(name: :asc), opts) do
        {:ok, records} -> records
        _ -> []
      end

    active_products =
      case Product
           |> Ash.Query.filter(status == :active)
           |> Ash.read(opts) do
        {:ok, products} -> products
        _ -> []
      end

    products_by_id = Map.new(active_products, &{&1.id, &1})

    variants =
      case Variant
           |> Ash.Query.sort(sku: :asc)
           |> Ash.read(opts) do
        {:ok, records} ->
          records
          |> Enum.filter(&Map.has_key?(products_by_id, &1.product_id))
          |> Enum.map(&Map.put(&1, :product, Map.fetch!(products_by_id, &1.product_id)))

        _ ->
          []
      end

    coupons =
      case Ash.read(Coupon |> Ash.Query.sort(code: :asc), opts) do
        {:ok, records} -> Enum.filter(records, &Algoie.Customers.coupon_valid_for_use?/1)
        _ -> []
      end

    delivery_rates =
      case Ash.read(
             DeliveryCharge
             |> Ash.Query.filter(active? == true and store_id == ^socket.assigns.store_id)
             |> Ash.Query.sort(priority: :desc, name: :asc),
             opts
           ) do
        {:ok, rates} -> rates
        _ -> []
      end

    unavailable_products =
      Enum.reject(active_products, fn product ->
        Enum.any?(variants, &(&1.product_id == product.id))
      end)

    socket
    |> assign(:customers, customers)
    |> assign(:variants, variants)
    |> assign(:coupons, coupons)
    |> assign(:delivery_rates, delivery_rates)
    |> assign(:unavailable_products, unavailable_products)
  end

  defp assign_form(socket, params) do
    defaults = %{
      "customer_mode" => "new",
      "country" => "Bangladesh",
      "shipping_amount" => "0",
      "product_search" => "",
      "items" => %{}
    }

    previous_items = current_items(socket)
    params = Map.merge(defaults, params)
    params = Map.put(params, "items", Map.merge(previous_items, params["items"] || %{}))
    incoming_search = String.trim(params["product_search"] || "")

    socket =
      if incoming_search != socket.assigns.catalog_search,
        do: assign(socket, :catalog_page, 1),
        else: socket

    subtotal = preview_subtotal(socket.assigns.variants, params["items"])
    params = apply_delivery_rate(params, socket.assigns[:delivery_rates] || [], subtotal)

    socket
    |> assign(:catalog_search, incoming_search)
    |> assign(:form, to_form(params, as: :order))
    |> assign(:customer_mode, params["customer_mode"])
    |> assign(:preview_subtotal, subtotal)
    |> assign_catalog()
  end

  defp assign_catalog(socket) do
    matching =
      Enum.filter(socket.assigns.variants, &catalog_match?(&1, socket.assigns.catalog_search))

    per_page = 8
    page_count = max(ceil(length(matching) / per_page), 1)
    page = min(socket.assigns.catalog_page, page_count)
    visible = Enum.slice(matching, (page - 1) * per_page, per_page)
    items = current_items(socket)

    selected =
      socket.assigns.variants
      |> Enum.map(fn variant -> {variant, parse_quantity(items[to_string(variant.id)])} end)
      |> Enum.filter(fn {_variant, quantity} -> quantity > 0 end)

    socket
    |> assign(:catalog_page, page)
    |> assign(:catalog_page_count, page_count)
    |> assign(:catalog_total, length(matching))
    |> assign(:visible_variants, visible)
    |> assign(:selected_variants, selected)
  end

  defp catalog_match?(_variant, ""), do: true

  defp catalog_match?(variant, search) do
    options = Enum.map_join(variant.option_values, " ", fn {key, value} -> "#{key} #{value}" end)

    haystack =
      "#{variant.product.name} #{variant.sku} #{variant.barcode} #{options}" |> String.downcase()

    String.contains?(haystack, String.downcase(search))
  end

  defp current_items(%{assigns: %{form: %{params: params}}}), do: params["items"] || %{}
  defp current_items(_socket), do: %{}

  defp preview_subtotal(variants, items) when is_map(items) do
    Enum.reduce(variants, Decimal.new(0), fn variant, total ->
      quantity = parse_quantity(items[to_string(variant.id)])
      Decimal.add(total, Decimal.mult(variant.price, Decimal.new(quantity)))
    end)
  end

  defp preview_subtotal(_, _), do: Decimal.new(0)

  defp line_items(items) do
    selected =
      items
      |> Enum.map(fn {id, quantity} -> %{variant_id: id, quantity: parse_quantity(quantity)} end)
      |> Enum.filter(&(&1.quantity > 0))

    if selected == [], do: {:error, :order_requires_items}, else: {:ok, selected}
  end

  defp customer_attrs(%{"customer_mode" => "existing", "customer_id" => id}) when id != "" do
    {:ok, %{customer_id: id, customer: nil}}
  end

  defp customer_attrs(params) do
    if blank?(params["name"]) do
      {:error, :customer_name_required}
    else
      {:ok,
       %{
         customer_id: nil,
         customer: %{name: params["name"], email: params["email"], phone: params["phone"]}
       }}
    end
  end

  defp address_attrs(params) do
    %{
      recipient_name: params["recipient_name"],
      phone: params["delivery_phone"],
      address_line1: params["address_line1"],
      address_line2: params["address_line2"],
      city: params["city"],
      area: params["area"],
      postal_code: params["postal_code"],
      country: params["country"],
      default?: params["save_address"] == "true"
    }
  end

  defp parse_quantity(value) when is_integer(value), do: max(value, 0)

  defp parse_quantity(value) when is_binary(value) do
    case Integer.parse(value) do
      {quantity, _} -> max(quantity, 0)
      _ -> 0
    end
  end

  defp parse_quantity(_), do: 0

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp error_message(:order_requires_items), do: "Add at least one product to the order."
  defp error_message(:customer_name_required), do: "Enter a customer name."
  defp error_message(:coupon_not_found), do: "That coupon code does not exist."
  defp error_message(:delivery_rate_not_found), do: "That delivery rate is no longer available."

  defp error_message(:coupon_not_valid_for_order),
    do: "That coupon is inactive, expired, exhausted, or below its minimum order value."

  defp error_message({:insufficient_stock, sku}), do: "Not enough stock is available for #{sku}."
  defp error_message(reason), do: "Could not create order: #{inspect(reason)}"

  defp format_money(%Decimal{} = amount),
    do: "৳" <> Decimal.to_string(Decimal.round(amount, 2), :normal)

  defp available_label(%{track_inventory?: false}), do: "Inventory not tracked"

  defp available_label(variant),
    do: "#{max(variant.stock - variant.reserved_quantity, 0)} available"

  defp maximum_quantity(%{track_inventory?: false}), do: 999_999
  defp maximum_quantity(variant), do: max(variant.stock - variant.reserved_quantity, 0)

  defp apply_delivery_rate(params, rates, subtotal) do
    case Enum.find(rates, &(to_string(&1.id) == params["delivery_charge_id"])) do
      nil ->
        Map.put(params, "shipping_amount", "0")

      rate ->
        free? =
          rate.free_delivery_threshold &&
            Decimal.compare(subtotal, rate.free_delivery_threshold) != :lt

        Map.put(
          params,
          "shipping_amount",
          if(free?, do: "0", else: Decimal.to_string(rate.charge, :normal))
        )
    end
  end

  defp selected_delivery_name(rates, id) do
    case Enum.find(rates, &(to_string(&1.id) == id)) do
      nil -> nil
      rate -> rate.name
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
