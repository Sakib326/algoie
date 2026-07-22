defmodule AlgoieWeb.BrandLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Products.Brand
  alias Algoie.AI.FormSuggestions
  alias Algoie.PlatformAISettings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :brands)
     |> assign(:page, 1)
     |> assign(:brands_page, nil)
     |> assign(:brands, [])
     |> assign(:ai_suggestions, %{})
     |> assign(:ai_loading, false)
     |> assign(
       :ai_enabled,
       "ai.use" in socket.assigns.store_permissions and
         PlatformAISettings.configured?(PlatformAISettings.get())
     )}
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
    |> assign(:ai_suggestions, %{})
    |> assign(:ai_loading, false)
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
  def handle_event("validate", %{"brand" => params}, socket) do
    params = maybe_put_store_id(params, socket)
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"brand" => params}, socket) do
    params = maybe_put_store_id(params, socket)

    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: AlgoieWeb.Scope.opts(socket)
         ) do
      {:ok, _brand} ->
        message =
          if socket.assigns.live_action == :new, do: "Brand created", else: "Brand updated"

        {:noreply, socket |> put_flash(:info, message) |> push_patch(to: ~p"/dashboard/brands")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Please correct the highlighted fields.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    brand = get_brand(socket, id)

    case Ash.destroy(brand, AlgoieWeb.Scope.opts(socket)) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete brand because it is in use.")}

      _ ->
        {:noreply, load_brands(socket)}
    end
  end

  def handle_event("suggest_fields", _params, %{assigns: %{live_action: :edit}} = socket) do
    values = Map.merge(brand_values(socket.assigns.brand), socket.assigns.form.params || %{})
    context = %{actor: socket.assigns.current_user, store_id: socket.assigns.store_id}

    {:noreply,
     socket
     |> assign(:ai_loading, true)
     |> start_async(:brand_suggestions, fn ->
       FormSuggestions.suggest("brand", values, context)
     end)}
  end

  def handle_event("suggest_fields", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:brand_suggestions, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, socket |> assign(:ai_suggestions, suggestions) |> assign(:ai_loading, false)}
  end

  def handle_async(:brand_suggestions, _result, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, false)
     |> put_flash(:error, "AI suggestions could not be generated. Please try again.")}
  end

  defp maybe_put_store_id(params, %{assigns: %{live_action: :new, store_id: store_id}}),
    do: Map.put(params, "store_id", store_id)

  defp maybe_put_store_id(params, _socket), do: params

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

  defp brand_values(brand) do
    Map.take(Map.from_struct(brand), [:name, :slug, :description, :meta_title, :meta_description])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value || ""} end)
  end
end
