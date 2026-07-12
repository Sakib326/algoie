defmodule AlgoieWeb.ProductLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Product

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_products(socket)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    product = get_product(socket, id)

    form =
      AshPhoenix.Form.for_update(product, :update,
        domain: Algoie.Products,
        as: "product"
      )

    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, product)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(Product, :create,
        domain: Algoie.Products,
        as: "product",
        params: %{"store_id" => socket.assigns.store_id}
      )

    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, nil)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Products")
    |> assign(:product, nil)
  end

  @impl true
  def handle_event("save", %{"product" => product_params}, socket) do
    save_product(socket, socket.assigns.live_action, product_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    product = get_product(socket, id)
    Ash.destroy!(product, actor: socket.assigns.current_user)
    {:noreply, load_products(socket)}
  end

  defp save_product(socket, :edit, product_params) do
    case Ash.update(socket.assigns.product, product_params, actor: socket.assigns.current_user) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully")
         |> load_products()}

      {:error, changeset} ->
        form =
          AshPhoenix.Form.for_update(changeset, :update, domain: Algoie.Products, as: "product")

        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp save_product(socket, :new, product_params) do
    params = Map.put(product_params, "store_id", socket.assigns.store_id)

    case Ash.create(Product, params, actor: socket.assigns.current_user) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product created successfully")
         |> load_products()}

      {:error, changeset} ->
        form =
          AshPhoenix.Form.for_create(changeset, :create, domain: Algoie.Products, as: "product")

        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp load_products(socket) do
    case Ash.read(Product, tenant: socket.assigns.tenant, actor: socket.assigns[:current_user]) do
      {:ok, products} -> assign(socket, :products, products)
      _ -> assign(socket, :products, [])
    end
  end

  defp get_product(socket, id) do
    case Ash.get(Product, id, tenant: socket.assigns.tenant, actor: socket.assigns[:current_user]) do
      {:ok, product} -> product
      _ -> nil
    end
  end
end
