defmodule AlgoieWeb.PublicURLTest do
  use ExUnit.Case, async: false

  alias AlgoieWeb.PublicURL

  setup do
    original = Application.get_env(:algoie, :app_url)
    on_exit(fn -> Application.put_env(:algoie, :app_url, original) end)
  end

  test "preserves the APP_URL scheme and non-default port" do
    Application.put_env(:algoie, :app_url, "https://app.example.test:8443")

    assert PublicURL.apex("/tenant/acme/dashboard") ==
             "https://app.example.test:8443/tenant/acme/dashboard"

    assert PublicURL.store("north", "/dashboard") ==
             "https://north.app.example.test:8443/dashboard"
  end

  test "builds canonical tenant and storefront URLs from one origin" do
    Application.put_env(:algoie, :app_url, "http://localhost:4100/")

    assert PublicURL.origin() == "http://localhost:4100/"
    assert PublicURL.tenant("demo") == "http://localhost:4100/tenant/demo/dashboard"
    assert PublicURL.store("shop") == "http://shop.localhost:4100/"
  end
end
