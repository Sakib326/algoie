defmodule AlgoieWeb.BrandLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Brand

  @impl true
  def mount(_params, _session, socket) do
    {:ok, 
     socket 
     |> assign(:active, :brands)
     |> assign(:page, 1)
     |> assign(:brands_page, nil)
     |> assign(:brands, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {p, _} when p > 0 -> p
        _ -> 1
      end

    socket =
      socket
      |> assign(:page, page)
      |> apply_action(socket.assigns.live_action, params)
      |> load_brands()

    {:noreply, socket}
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
    Ash.destroy!(brand, AlgoieWeb.Scope.opts(socket))
    {:noreply, load_brands(socket)}
  end

  defp save_brand(socket, :edit, params) do
    case Ash.update(socket.assigns.brand, params, AlgoieWeb.Scope.opts(socket)) do
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

    case Ash.create(Brand, params, AlgoieWeb.Scope.opts(socket)) do
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
    limit = 12
    offset = (socket.assigns.page - 1) * limit
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, offset: offset, count: true)

    case Ash.read(Brand, opts) do
      {:ok, page_result} -> 
        socket
        |> assign(:brands, page_result.results)
        |> assign(:brands_page, page_result)
      _ -> 
        socket
        |> assign(:brands, [])
        |> assign(:brands_page, nil)
    end
  end

  defp get_brand(socket, id) do
    case Ash.get(Brand, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, b} -> b
      _ -> nil
    end
  end
end
