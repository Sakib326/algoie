defmodule AlgoieWeb.StorefrontProductLive.Show do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  alias Algoie.Products.{Product, Variant}

  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tenant = socket.assigns.tenant

    product =
      case Ash.get(Product, id, tenant: tenant, authorize?: false) do
        {:ok, p} -> p
        _ -> nil
      end

    variants =
      if product do
        Variant
        |> Ash.Query.filter(product_id == ^product.id)
        |> Ash.Query.sort(:price)
        |> Ash.read!(tenant: tenant, authorize?: false)
      else
        []
      end

    {:ok,
     socket
     |> assign(:page_title, product.name || "Product")
     |> assign(:product, product)
     |> assign(:variants, variants)}
  end
end
