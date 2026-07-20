defmodule AlgoieWeb.StorefrontCheckoutController do
  use AlgoieWeb, :controller

  require Ash.Query

  alias Algoie.Orders.{Order, OrderWorkflow}
  alias Algoie.Storefront.Cart
  alias Algoie.Stores.DeliveryCharge

  @cart_key "storefront_cart"

  def new(conn, _params) do
    context = context(conn)
    cart = Cart.load(context.tenant, context.store_id, get_session(conn, @cart_key))

    if cart.items == [] do
      conn |> put_flash(:error, "Your cart is empty") |> redirect(to: ~p"/cart")
    else
      render_checkout(conn, context, cart, %{})
    end
  end

  def create(conn, %{"checkout" => params}) do
    context = context(conn)
    cart = Cart.load(context.tenant, context.store_id, get_session(conn, @cart_key))
    rates = delivery_rates(context)

    with :ok <- validate_checkout(params, cart, rates),
         {:ok, order} <-
           OrderWorkflow.create_order(context.tenant, order_attrs(context, cart, params), nil) do
      conn
      |> delete_session(@cart_key)
      |> put_session("storefront_last_order_id", to_string(order.id))
      |> put_flash(:info, "Thank you. Your order has been placed.")
      |> redirect(to: ~p"/order-confirmation/#{order.id}")
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, error_message(reason))
        |> render_checkout(context, cart, params)
    end
  end

  def confirmation(conn, %{"id" => id}) do
    context = context(conn)

    if get_session(conn, "storefront_last_order_id") == id do
      case Order
           |> Ash.Query.filter(id == ^id and store_id == ^context.store_id)
           |> Ash.read_one(tenant: context.tenant, authorize?: false) do
        {:ok, order} ->
          conn
          |> put_view(html: AlgoieWeb.StorefrontHTML)
          |> render(:confirmation, Map.merge(context, %{order: order}))

        _ ->
          not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  defp render_checkout(conn, context, cart, params) do
    rates = delivery_rates(context)

    defaults = %{
      "country" => "Bangladesh",
      "name" => context.current_customer && context.current_customer.name,
      "email" => context.current_customer && to_string(context.current_customer.email),
      "phone" => context.current_customer && context.current_customer.phone
    }

    conn
    |> put_view(html: AlgoieWeb.StorefrontHTML)
    |> render(
      :checkout,
      Map.merge(context, %{
        cart: cart,
        delivery_rates: rates,
        form: Phoenix.Component.to_form(Map.merge(defaults, params), as: :checkout)
      })
    )
  end

  defp order_attrs(context, cart, params) do
    %{
      store_id: context.store_id,
      customer: %{
        name: params["name"],
        email: params["email"],
        phone: params["phone"]
      },
      address: %{
        recipient_name: params["name"],
        phone: params["phone"],
        address_line1: params["address_line1"],
        address_line2: params["address_line2"],
        city: params["city"],
        area: params["area"],
        postal_code: params["postal_code"],
        country: params["country"]
      },
      variant_quantities:
        Enum.map(cart.items, &%{variant_id: &1.variant.id, quantity: &1.quantity}),
      coupon_code: params["coupon_code"],
      delivery_charge_id: blank_to_nil(params["delivery_charge_id"]),
      notes: params["notes"]
    }
  end

  defp validate_checkout(params, cart, rates) do
    cond do
      cart.items == [] -> {:error, :order_requires_items}
      blank?(params["name"]) -> {:error, "Name is required"}
      blank?(params["phone"]) -> {:error, "Phone is required"}
      blank?(params["address_line1"]) -> {:error, "Address is required"}
      blank?(params["city"]) -> {:error, "City is required"}
      rates != [] and blank?(params["delivery_charge_id"]) -> {:error, "Select a delivery option"}
      true -> :ok
    end
  end

  defp delivery_rates(context) do
    DeliveryCharge
    |> Ash.Query.filter(active? == true and store_id == ^context.store_id)
    |> Ash.Query.sort(priority: :desc, name: :asc)
    |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)
  end

  defp not_found(conn) do
    conn |> put_status(:not_found) |> put_view(AlgoieWeb.ErrorHTML) |> render(:"404")
  end

  defp context(conn) do
    %{
      tenant: get_session(conn, "store_tenant"),
      store_id: get_session(conn, "store_id"),
      store: conn.assigns.store,
      current_customer: conn.assigns.current_customer
    }
  end

  defp blank?(value), do: String.trim(value || "") == ""
  defp blank_to_nil(value), do: if(blank?(value), do: nil, else: String.trim(value))

  defp error_message(message) when is_binary(message), do: message
  defp error_message(:order_requires_items), do: "Your cart is empty"
  defp error_message(:coupon_not_found), do: "Coupon code was not found"
  defp error_message(:coupon_not_valid_for_order), do: "Coupon cannot be used for this order"
  defp error_message(:delivery_rate_not_found), do: "Select a valid delivery option"
  defp error_message({:insufficient_stock, sku}), do: "Not enough stock for #{sku}"
  defp error_message(:variant_not_found), do: "A cart product is no longer available"
  defp error_message(reason), do: "Order could not be placed: #{inspect(reason)}"
end
