defmodule AlgoieWeb.CategoryLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_categories(socket)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    category = get_category(socket, id)

    socket
    |> assign(:page_title, "Edit Category")
    |> assign(:category, category)
    |> assign(:form, to_form(Ash.Changeset.for_update(category, :update)))
  end

  defp apply_action(socket, :new, _params) do
    changeset = Ash.Changeset.for_create(Category, :create, %{store_id: socket.assigns.store_id})

    socket
    |> assign(:page_title, "New Category")
    |> assign(:category, nil)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Categories")
    |> assign(:category, nil)
  end

  @impl true
  def handle_event("save", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.live_action, category_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = get_category(socket, id)
    Ash.destroy!(category, actor: :system)
    {:noreply, load_categories(socket)}
  end

  defp save_category(socket, :edit, category_params) do
    case Ash.update(socket.assigns.category, category_params, actor: :system) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated successfully")
         |> load_categories()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_category(socket, :new, category_params) do
    params = Map.put(category_params, "store_id", socket.assigns.store_id)

    case Ash.create(Category, params, actor: :system) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created successfully")
         |> load_categories()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_categories(socket) do
    case Ash.read(Category, tenant: socket.assigns.tenant, authorize?: false) do
      {:ok, categories} ->
        assign(socket, :categories, categories)

      _ ->
        assign(socket, :categories, [])
    end
  end

  defp get_category(socket, id) do
    case Ash.get(Category, id, tenant: socket.assigns.tenant, authorize?: false) do
      {:ok, category} -> category
      _ -> nil
    end
  end
end
