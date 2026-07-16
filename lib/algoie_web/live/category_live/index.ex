defmodule AlgoieWeb.CategoryLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:active, :categories) |> load_categories()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    category = get_category(socket, id)
    form = AshPhoenix.Form.for_update(category, :update, domain: Algoie.Products, as: "category")

    socket
    |> assign(:page_title, "Edit Category")
    |> assign(:category, category)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(Category, :create,
        domain: Algoie.Products,
        as: "category",
        params: %{"store_id" => socket.assigns.store_id}
      )

    socket
    |> assign(:page_title, "New Category")
    |> assign(:category, nil)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Categories") |> assign(:category, nil)
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    save_category(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = get_category(socket, id)
    Ash.destroy!(category, AlgoieWeb.Scope.opts(socket))
    {:noreply, load_categories(socket)}
  end

  defp save_category(socket, :edit, params) do
    case Ash.update(socket.assigns.category, params, AlgoieWeb.Scope.opts(socket)) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Category updated") |> load_categories()}

      {:error, cs} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               AshPhoenix.Form.for_update(cs, :update, domain: Algoie.Products, as: "category")
             )
         )}
    end
  end

  defp save_category(socket, :new, params) do
    params = Map.put(params, "store_id", socket.assigns.store_id)

    case Ash.create(Category, params, AlgoieWeb.Scope.opts(socket)) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Category created") |> load_categories()}

      {:error, cs} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               AshPhoenix.Form.for_create(cs, :create, domain: Algoie.Products, as: "category")
             )
         )}
    end
  end

  defp load_categories(socket) do
    case Ash.read(Category, AlgoieWeb.Scope.opts(socket)) do
      {:ok, cats} -> assign(socket, :categories, cats)
      _ -> assign(socket, :categories, [])
    end
  end

  defp get_category(socket, id) do
    case Ash.get(Category, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, c} -> c
      _ -> nil
    end
  end
end
