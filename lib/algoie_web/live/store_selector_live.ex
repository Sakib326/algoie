defmodule AlgoieWeb.StoreSelectorLive do
  use AlgoieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    owner_tenants = Algoie.Accounts.UserContext.load_owner_tenants(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(:page_title, "Select Store")
     |> assign(:stores, socket.assigns.user_stores)
     |> assign(:owner_tenants, owner_tenants)
     |> assign(:store_form, store_form(owner_tenants))}
  end

  @impl true
  def handle_event("validate_store", %{"store" => params}, socket) do
    params = maybe_derive_slug(params)
    {:noreply, assign(socket, :store_form, store_form(socket.assigns.owner_tenants, params))}
  end

  def handle_event("create_store", %{"store" => params}, socket) do
    tenant = selected_tenant(socket.assigns.owner_tenants, params["tenant"])

    case Algoie.Stores.StoreCreator.create_for_owner(socket.assigns.current_user, tenant, params) do
      {:ok, store} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{store.name} was created")
         |> redirect(to: "/switch-store/#{store.id}")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:store_form, store_form(socket.assigns.owner_tenants, params))
         |> put_flash(:error, error_text(error))}
    end
  end

  defp store_form(owner_tenants, params \\ %{}) do
    default_tenant = owner_tenants |> List.first() |> then(&(&1 && &1.tenant))
    defaults = %{"name" => "", "slug" => "", "tenant" => default_tenant}
    to_form(Map.merge(defaults, params), as: :store)
  end

  defp maybe_derive_slug(%{"name" => name, "slug" => slug} = params) when slug in [nil, ""] do
    Map.put(params, "slug", Algoie.Stores.StoreCreator.normalize_slug(name))
  end

  defp maybe_derive_slug(params), do: params

  defp selected_tenant([tenant], _submitted), do: tenant.tenant

  defp selected_tenant(owner_tenants, submitted) do
    case Enum.find(owner_tenants, &(&1.tenant == submitted)) do
      nil -> nil
      tenant -> tenant.tenant
    end
  end

  defp error_text(error) when is_binary(error), do: error
  defp error_text(:forbidden), do: "Only a tenant owner can create another store"
  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()
end
