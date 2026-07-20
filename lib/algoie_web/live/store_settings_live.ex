defmodule AlgoieWeb.StoreSettingsLive do
  use AlgoieWeb, :live_view

  alias Algoie.Stores.Store

  @impl true
  def mount(_params, _session, socket) do
    case Ash.get(Store, socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, store} ->
        form = AshPhoenix.Form.for_update(store, :update, domain: Algoie.Stores, as: "store")

        {:ok,
         socket
         |> assign(:active, :settings)
         |> assign(:page_title, "Store settings")
         |> assign(:store, store)
         |> assign(:form, to_form(form))}

      _ ->
        {:ok,
         socket
         |> assign(:active, :settings)
         |> assign(:page_title, "Store settings")
         |> assign(:store, nil)
         |> assign(:form, nil)}
    end
  end

  @impl true
  def handle_event("validate", %{"store" => params}, socket) do
    params = Map.put(params, "currency", "BDT")
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"store" => params}, socket) do
    params = Map.put(params, "currency", "BDT")

    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: AlgoieWeb.Scope.opts(socket)
         ) do
      {:ok, store} ->
        form = AshPhoenix.Form.for_update(store, :update, domain: Algoie.Stores, as: "store")

        {:noreply,
         socket
         |> assign(:store, store)
         |> assign(:store_name, store.name)
         |> assign(:form, to_form(form))
         |> put_flash(:info, "Store settings saved")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Please correct the highlighted fields.")}
    end
  end
end
