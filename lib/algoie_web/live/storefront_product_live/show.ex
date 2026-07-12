defmodule AlgoieWeb.StorefrontProductLive.Show do
  use AlgoieWeb, :live_view

  on_mount {AlgoieWeb.Live.OnStoreMount, :default}

  alias Algoie.Products.Product

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    product =
      case Ash.get(Product, id,
             tenant: socket.assigns.tenant,
             actor: socket.assigns[:current_user]
           ) do
        {:ok, p} -> p
        _ -> nil
      end

    {:ok, socket |> assign(:page_title, product.name || "Product") |> assign(:product, product)}
  end
end
