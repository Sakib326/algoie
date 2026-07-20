defmodule Algoie.Storefront.CartTest do
  use ExUnit.Case, async: true

  alias Algoie.Storefront.Cart

  test "a cart is isolated to its resolved store" do
    cart = Cart.put(nil, "store-a", "variant-a", 2)

    assert cart == %{
             "store_id" => "store-a",
             "items" => %{"variant-a" => 2}
           }

    assert Cart.normalize(cart, "store-b") == %{
             "store_id" => "store-b",
             "items" => %{}
           }
  end

  test "quantities are bounded and invalid values remove an item" do
    cart = Cart.put(nil, "store-a", "variant-a", 500)
    assert cart["items"]["variant-a"] == 99

    cart = Cart.put(cart, "store-a", "variant-a", 0)
    assert cart["items"] == %{}
  end

  test "quantity parser rejects malformed and negative input" do
    assert Cart.parse_quantity("3") == 3
    assert Cart.parse_quantity("500") == 99
    assert Cart.parse_quantity("-1") == 0
    assert Cart.parse_quantity("wrong") == 0
  end
end
