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
    form = AshPhoenix.Form.for_update(brand, :update, domain: Algoie.Products, as: "brand")

    socket
    |> assign(:page_title, "Edit Brand")
    |> assign(:brand, brand)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(Brand, :create,
        domain: Algoie.Products,
        as: "brand",
        params: %{"store_id" => socket.assigns.store_id}
      )

    socket
    |> assign(:page_title, "New Brand")
    |> assign(:brand, nil)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Brands") |> assign(:brand, nil)
  end

  @impl true
  def handle_event("save", %{"brand" => params}, socket) do
    save_brand(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    brand = get_brand(socket, id)
    Ash.destroy!(brand, actor: socket.assigns.current_user)
    {:noreply, load_brands(socket)}
  end

  defp save_brand(socket, :edit, params) do
    case Ash.update(socket.assigns.brand, params, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Brand updated") |> load_brands()}

      {:error, cs} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               AshPhoenix.Form.for_update(cs, :update, domain: Algoie.Products, as: "brand")
             )
         )}
    end
  end

  defp save_brand(socket, :new, params) do
    params = Map.put(params, "store_id", socket.assigns.store_id)

    case Ash.create(Brand, params, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Brand created") |> load_brands()}

      {:error, cs} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               AshPhoenix.Form.for_create(cs, :create, domain: Algoie.Products, as: "brand")
             )
         )}
    end
  end

  defp load_brands(socket) do
    case Ash.read(Brand, tenant: socket.assigns.tenant, actor: socket.assigns[:current_user]) do
      {:ok, brands} -> assign(socket, :brands, brands)
      _ -> assign(socket, :brands, [])
    end
  end

  defp get_brand(socket, id) do
    case Ash.get(Brand, id, tenant: socket.assigns.tenant, actor: socket.assigns[:current_user]) do
      {:ok, b} -> b
      _ -> nil
    end
  end
end
