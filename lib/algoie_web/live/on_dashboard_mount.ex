defmodule AlgoieWeb.Live.OnDashboardMount do
  @moduledoc "Authorizes tenant dashboard access against the slug-resolved store."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  @view_permissions %{
    AlgoieWeb.ProductLive.Index => "catalog.view",
    AlgoieWeb.ProductLive.Wizard => "catalog.manage",
    AlgoieWeb.CategoryLive.Index => "catalog.view",
    AlgoieWeb.BrandLive.Index => "catalog.view",
    AlgoieWeb.MediaLive.Index => "catalog.view",
    AlgoieWeb.InventoryLive.Index => "inventory.view",
    AlgoieWeb.OrderLive.Index => "orders.view",
    AlgoieWeb.OrderLive.New => "orders.manage",
    AlgoieWeb.OrderLive.Show => "orders.view",
    AlgoieWeb.OrderLive.Invoice => "orders.view",
    AlgoieWeb.CustomerLive.Index => "customers.view",
    AlgoieWeb.CustomerLive.New => "customers.manage",
    AlgoieWeb.CustomerLive.Show => "customers.view",
    AlgoieWeb.CouponLive.Index => "discounts.view",
    AlgoieWeb.DeliveryChargeLive.Index => "discounts.view",
    AlgoieWeb.SalesReportLive => "reports.view",
    AlgoieWeb.RepeatOrderReportLive => "reports.view",
    AlgoieWeb.ConversationLive.Index => "engagement.view",
    AlgoieWeb.CampaignLive.Index => "engagement.view",
    AlgoieWeb.AiAssistantLive => "ai.use",
    AlgoieWeb.StoreSettingsLive => "settings.view",
    AlgoieWeb.SocialPublishingLive => "social.view",
    AlgoieWeb.StoreEmailSettingsLive => "settings.view",
    AlgoieWeb.TeamLive.Index => "team.view"
  }

  def on_mount(:default, _params, session, socket) do
    with user when not is_nil(user) <- socket.assigns[:current_user],
         tenant when is_binary(tenant) <- session["store_tenant"],
         store_id when is_binary(store_id) <- session["store_id"],
         {:ok, access} <- Algoie.Accounts.UserContext.find_store_access(user.id, store_id),
         true <- access.tenant == tenant,
         true <- allowed_view?(socket.view, access.permissions) do
      tenant_slugs =
        Algoie.Accounts.TenantPortal.list_for_user(user.id)
        |> Map.new(&{&1.tenant, &1.slug})

      stores =
        Algoie.Accounts.UserContext.load_all_user_stores(user.id)
        |> Enum.map(&Map.put(&1, :tenant_slug, tenant_slugs[&1.tenant]))

      {:cont,
       socket
       |> assign(:tenant, tenant)
       |> assign(:store_id, store_id)
       |> assign(:store_name, access.store_name)
       |> assign(:store_role, Atom.to_string(access.role))
       |> assign(:store_permissions, access.permissions)
       |> assign(:user_stores, stores)
       |> assign(:current_scope, %{user: user})}
    else
      nil ->
        {:halt, redirect(socket, to: "/sign-in")}

      _ ->
        {:halt,
         socket
         |> put_flash(:error, "You do not have permission to access that area")
         |> redirect(to: "/dashboard")}
    end
  end

  defp allowed_view?(AlgoieWeb.DashboardLive, _permissions), do: true

  defp allowed_view?(AlgoieWeb.SocialPublishingLive, permissions) do
    "social.view" in permissions or "settings.view" in permissions or
      "settings.manage" in permissions
  end

  defp allowed_view?(view, permissions), do: Map.get(@view_permissions, view) in permissions
end
