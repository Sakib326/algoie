defmodule AlgoieWeb.StorefrontCartController do
  use AlgoieWeb, :controller

  alias Algoie.Storefront.Cart

  @cart_key "storefront_cart"

  def show(conn, _params) do
    context = context(conn)
    cart = Cart.load(context.tenant, context.store_id, get_session(conn, @cart_key))

    conn
    |> put_view(html: AlgoieWeb.StorefrontHTML)
    |> render(:cart, Map.merge(context, %{cart: cart}))
  end

  def add(conn, %{"variant_id" => variant_id} = params) do
    context = context(conn)
    quantity = max(Cart.parse_quantity(params["quantity"] || "1"), 1)
    current = Cart.load(context.tenant, context.store_id, get_session(conn, @cart_key))

    if Enum.any?(current.items, &(&1.variant.id == variant_id)) ||
         valid_variant?(context, variant_id) do
      cart = Cart.put(get_session(conn, @cart_key), context.store_id, variant_id, quantity)

      conn
      |> put_session(@cart_key, cart)
      |> put_flash(:info, "Product added to your cart")
      |> redirect(to: ~p"/cart")
    else
      conn |> put_flash(:error, "Product is unavailable") |> redirect(to: ~p"/products")
    end
  end

  def update(conn, %{"items" => items}) do
    context = context(conn)

    cart =
      Enum.reduce(items, get_session(conn, @cart_key), fn {variant_id, quantity}, cart ->
        Cart.put(cart, context.store_id, variant_id, Cart.parse_quantity(quantity))
      end)

    conn
    |> put_session(@cart_key, cart)
    |> put_flash(:info, "Cart updated")
    |> redirect(to: ~p"/cart")
  end

  def update(conn, _params), do: redirect(conn, to: ~p"/cart")

  def remove(conn, %{"variant_id" => variant_id}) do
    context = context(conn)
    cart = Cart.remove(get_session(conn, @cart_key), context.store_id, variant_id)

    conn
    |> put_session(@cart_key, cart)
    |> put_flash(:info, "Product removed")
    |> redirect(to: ~p"/cart")
  end

  defp valid_variant?(context, variant_id) do
    Cart.load(context.tenant, context.store_id, %{
      "store_id" => to_string(context.store_id),
      "items" => %{variant_id => 1}
    }).items != []
  end

  defp context(conn) do
    %{
      tenant: get_session(conn, "store_tenant"),
      store_id: get_session(conn, "store_id"),
      store: conn.assigns.store,
      current_customer: conn.assigns.current_customer
    }
  end
end
