defmodule AlgoieWeb.LayoutsPermissionsTest do
  use ExUnit.Case, async: true
  use AlgoieWeb, :html

  import Phoenix.LiveViewTest

  alias AlgoieWeb.Layouts

  test "dashboard navigation hides modules without view permission" do
    html = render_dashboard(["orders.view"])

    assert html =~ "Orders"
    refute html =~ ">Customers<"
    refute html =~ ">Products<"
    refute html =~ "Team &amp; Roles"
  end

  test "dashboard navigation shows a module with view permission" do
    html = render_dashboard(["customers.view"])

    assert html =~ ">Customers<"
    refute html =~ ">Orders<"
  end

  defp render_dashboard(permissions) do
    store_id = Ecto.UUID.generate()

    render_component(&dashboard_component/1,
      flash: %{},
      current_user: %{email: "staff@example.com", name: "Staff"},
      tenant: "tenant_test",
      store_id: store_id,
      store_name: "Test Store",
      user_stores: [
        %{
          store_id: store_id,
          store_name: "Test Store",
          tenant: "tenant_test",
          tenant_slug: "test-workspace",
          permissions: permissions
        }
      ],
      page_title: "Dashboard",
      active: :overview
    )
  end

  defp dashboard_component(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_user={@current_user}
      tenant={@tenant}
      store_id={@store_id}
      store_name={@store_name}
      user_stores={@user_stores}
      page_title={@page_title}
      active={@active}
    >
      Dashboard content
    </Layouts.dashboard>
    """
  end
end
