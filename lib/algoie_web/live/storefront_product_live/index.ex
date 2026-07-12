defmodule AlgoieWeb.StorefrontProductLive.Index do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  alias Algoie.Products.Product

  @impl true
  def mount(_params, _session, socket) do
    products =
      case Ash.read(Product, tenant: socket.assigns.tenant, actor: socket.assigns[:current_user]) do
        {:ok, products} -> Enum.filter(products, &(&1.status == :active))
        _ -> []
      end

    {:ok, socket |> assign(:page_title, "Products") |> assign(:products, products)}
  end
end
