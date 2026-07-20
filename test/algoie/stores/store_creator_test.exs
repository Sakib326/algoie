defmodule Algoie.Stores.StoreCreatorTest do
  use ExUnit.Case, async: true

  alias Algoie.Stores.StoreCreator

  test "normalizes a storefront slug" do
    assert StoreCreator.normalize_slug("  Northwind Outlet!  ") == "northwind-outlet"
    assert StoreCreator.normalize_slug("ঢাকা Store 2") == "store-2"
  end
end
