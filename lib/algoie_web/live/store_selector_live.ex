defmodule AlgoieWeb.StoreSelectorLive do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    stores = socket.assigns[:user_stores] || []

    {:ok,
     socket
     |> assign(:page_title, "Select Store")
     |> assign(:stores, stores)}
  end

  @impl true
  def handle_event("select_store", %{"store_id" => store_id}, socket) do
    stores = socket.assigns.stores

    case Enum.find(stores, &(&1.store_id == store_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Store not found")}

      store ->
        {:noreply,
         socket
         |> push_navigate(to: "/switch-store/#{store.store_id}")}
    end
  end
end
