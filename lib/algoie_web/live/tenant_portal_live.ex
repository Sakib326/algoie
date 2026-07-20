defmodule AlgoieWeb.TenantPortalLive do
  use AlgoieWeb, :live_view

  alias Algoie.Accounts.{StorePermissions, TenantPortal}
  alias Algoie.Stores.StoreCreator

  @impl true
  def mount(%{"tenant_slug" => slug}, _session, socket) do
    case TenantPortal.get_for_user(socket.assigns.current_user.id, slug) do
      {:ok, tenant} ->
        {:ok,
         socket
         |> assign(:page_title, "#{tenant.name} · Control center")
         |> assign(:tenant_account, tenant)
         |> assign(:manager?, tenant.role in [:owner, :admin])
         |> assign(:permission_options, StorePermissions.all())
         |> assign(:store_form, store_form())
         |> assign(:member_form, member_form())
         |> load_portal()}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have access to that tenant")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("validate_store", %{"store" => params}, socket) do
    params = maybe_derive_slug(params)
    {:noreply, assign(socket, :store_form, store_form(params))}
  end

  def handle_event("create_store", %{"store" => params}, socket) do
    if socket.assigns.manager? do
      case StoreCreator.create_for_owner(
             socket.assigns.current_user,
             socket.assigns.tenant_account.tenant,
             params
           ) do
        {:ok, store} ->
          {:noreply,
           socket
           |> assign(:store_form, store_form())
           |> load_portal()
           |> put_flash(:info, "#{store.name} was created")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, error_text(error))}
      end
    else
      {:noreply, put_flash(socket, :error, "Tenant administrator access is required")}
    end
  end

  def handle_event("add_member", %{"member" => params}, socket) do
    if socket.assigns.manager? do
      case TenantPortal.add_member(
             socket.assigns.current_user,
             socket.assigns.tenant_account,
             params
           ) do
        {:ok, user} ->
          {:noreply,
           socket
           |> assign(:member_form, member_form())
           |> load_portal()
           |> put_flash(:info, "#{user.name || user.email} now has tenant access")}

        {:error, error} ->
          {:noreply,
           socket
           |> assign(:member_form, member_form(params))
           |> put_flash(:error, error_text(error))}
      end
    else
      {:noreply, put_flash(socket, :error, "Tenant administrator access is required")}
    end
  end

  def handle_event("remove_store_access", %{"user_id" => user_id, "store_id" => store_id}, socket) do
    case TenantPortal.remove_store_access(
           socket.assigns.current_user,
           socket.assigns.tenant_account,
           user_id,
           store_id
         ) do
      :ok -> {:noreply, socket |> load_portal() |> put_flash(:info, "Store access removed")}
      {:ok, _} -> {:noreply, socket |> load_portal() |> put_flash(:info, "Store access removed")}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("change_tenant_role", %{"membership_id" => id, "role" => role}, socket) do
    parsed_role = if role == "admin", do: :admin, else: :member

    case TenantPortal.change_member_role(
           socket.assigns.current_user,
           socket.assigns.tenant_account,
           id,
           parsed_role
         ) do
      {:ok, _} -> {:noreply, socket |> load_portal() |> put_flash(:info, "Tenant role updated")}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("remove_tenant_member", %{"membership_id" => id}, socket) do
    case TenantPortal.remove_member(
           socket.assigns.current_user,
           socket.assigns.tenant_account,
           id
         ) do
      :ok -> {:noreply, socket |> load_portal() |> put_flash(:info, "Member removed")}
      {:ok, _} -> {:noreply, socket |> load_portal() |> put_flash(:info, "Member removed")}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  defp load_portal(socket) do
    tenant = socket.assigns.tenant_account
    stores = TenantPortal.load_stores(tenant, socket.assigns.current_user.id)

    socket
    |> assign(:stores, stores)
    |> assign(:summary, TenantPortal.summary(tenant, stores))
    |> assign(:team, TenantPortal.load_team(tenant))
  end

  defp store_form(params \\ %{}),
    do: to_form(Map.merge(%{"name" => "", "slug" => ""}, params), as: :store)

  defp member_form(params \\ %{}) do
    defaults = %{
      "name" => "",
      "email" => "",
      "password" => "",
      "store_ids" => [],
      "permissions" => StorePermissions.defaults(:staff)
    }

    to_form(Map.merge(defaults, params), as: :member)
  end

  defp maybe_derive_slug(%{"name" => name, "slug" => slug} = params) when slug in [nil, ""],
    do: Map.put(params, "slug", StoreCreator.normalize_slug(name))

  defp maybe_derive_slug(params), do: params

  defp tenant_path(slug, :dashboard), do: "/tenant/#{slug}/dashboard"
  defp tenant_path(slug, :stores), do: "/tenant/#{slug}/stores"
  defp tenant_path(slug, :team), do: "/tenant/#{slug}/team"
  defp tenant_path(slug, :reports), do: "/tenant/#{slug}/reports"
  defp tenant_path(slug, :settings), do: "/tenant/#{slug}/settings"

  defp error_text(error) when is_binary(error), do: error
  defp error_text(:forbidden), do: "You are not allowed to perform this action"
  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()
end
