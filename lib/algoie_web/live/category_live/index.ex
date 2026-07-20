defmodule AlgoieWeb.CategoryLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :categories)
     |> assign(:page, 1)
     |> assign(:categories_page, nil)
     |> assign(:categories, [])}
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
      |> load_categories()

    {:noreply, socket}
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
  def handle_event("validate", %{"category" => params}, socket) do
    params = maybe_put_store_id(params, socket)
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"category" => params}, socket) do
    params = maybe_put_store_id(params, socket)

    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: AlgoieWeb.Scope.opts(socket)
         ) do
      {:ok, _category} ->
        message =
          if socket.assigns.live_action == :new, do: "Category created", else: "Category updated"

        {:noreply,
         socket |> put_flash(:info, message) |> push_patch(to: ~p"/dashboard/categories")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Please correct the highlighted fields.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = get_category(socket, id)

    case Ash.destroy(category, AlgoieWeb.Scope.opts(socket)) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete category because it is in use.")}

      _ ->
        {:noreply, load_categories(socket)}
    end
  end

  defp maybe_put_store_id(params, %{assigns: %{live_action: :new, store_id: store_id}}),
    do: Map.put(params, "store_id", store_id)

  defp maybe_put_store_id(params, _socket), do: params

  defp load_categories(socket) do
    limit = 12
    offset = (socket.assigns.page - 1) * limit
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, offset: offset, count: true)

    case Ash.read(Category, opts) do
      {:ok, page_result} ->
        socket
        |> assign(:categories, page_result.results)
        |> assign(:categories_page, page_result)

      _ ->
        socket
        |> assign(:categories, [])
        |> assign(:categories_page, nil)
    end
  end

  defp get_category(socket, id) do
    case Ash.get(Category, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, c} -> c
      _ -> nil
    end
  end
end
