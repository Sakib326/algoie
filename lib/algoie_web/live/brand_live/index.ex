defmodule AlgoieWeb.BrandLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Brand

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_brands(socket)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    brand = get_brand(socket, id)

    socket
    |> assign(:page_title, "Edit Brand")
    |> assign(:brand, brand)
    |> assign(:form, to_form(Ash.Changeset.for_update(brand, :update)))
  end

  defp apply_action(socket, :new, _params) do
    changeset = Ash.Changeset.for_create(Brand, :create, %{store_id: socket.assigns.store_id})

    socket
    |> assign(:page_title, "New Brand")
    |> assign(:brand, nil)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Brands")
    |> assign(:brand, nil)
  end

  @impl true
  def handle_event("save", %{"brand" => brand_params}, socket) do
    save_brand(socket, socket.assigns.live_action, brand_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    brand = get_brand(socket, id)
    Ash.destroy!(brand, actor: :system)
    {:noreply, load_brands(socket)}
  end

  defp save_brand(socket, :edit, brand_params) do
    case Ash.update(socket.assigns.brand, brand_params, actor: :system) do
      {:ok, _brand} ->
        {:noreply,
         socket
         |> put_flash(:info, "Brand updated successfully")
         |> load_brands()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_brand(socket, :new, brand_params) do
    params = Map.put(brand_params, "store_id", socket.assigns.store_id)

    case Ash.create(Brand, params, actor: :system) do
      {:ok, _brand} ->
        {:noreply,
         socket
         |> put_flash(:info, "Brand created successfully")
         |> load_brands()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_brands(socket) do
    case Ash.read(Brand, tenant: socket.assigns.tenant, authorize?: false) do
      {:ok, brands} ->
        assign(socket, :brands, brands)

      _ ->
        assign(socket, :brands, [])
    end
  end

  defp get_brand(socket, id) do
    case Ash.get(Brand, id, tenant: socket.assigns.tenant, authorize?: false) do
      {:ok, brand} -> brand
      _ -> nil
    end
  end
end
