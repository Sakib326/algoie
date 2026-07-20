defmodule AlgoieWeb.RouterHostSeparationTest do
  use ExUnit.Case, async: true

  test "apex dashboard resolves to SaaS administration" do
    route = Phoenix.Router.route_info(AlgoieWeb.Router, "GET", "/dashboard", "www.example.com")
    assert route.plug == Phoenix.LiveView.Plug
    assert route.log_module == AlgoieWeb.PlatformAdminLive
  end

  test "store slug dashboard resolves to tenant administration" do
    route =
      Phoenix.Router.route_info(AlgoieWeb.Router, "GET", "/dashboard", "demo.www.example.com")

    assert route.plug == Phoenix.LiveView.Plug
    assert route.log_module == AlgoieWeb.DashboardLive
  end

  test "SaaS operational pages remain apex-only" do
    for path <- ["/admin/tenants", "/admin/stores", "/admin/email"] do
      route = Phoenix.Router.route_info(AlgoieWeb.Router, "GET", path, "www.example.com")
      assert route.log_module == AlgoieWeb.PlatformAdminLive
    end
  end

  test "sales reporting resolves inside the tenant dashboard" do
    route =
      Phoenix.Router.route_info(
        AlgoieWeb.Router,
        "GET",
        "/dashboard/reports/sales",
        "demo.www.example.com"
      )

    assert route.plug == Phoenix.LiveView.Plug
    assert route.log_module == AlgoieWeb.SalesReportLive
  end

  test "repeat-order reporting resolves inside the tenant dashboard" do
    route =
      Phoenix.Router.route_info(
        AlgoieWeb.Router,
        "GET",
        "/dashboard/reports/repeat-orders",
        "demo.www.example.com"
      )

    assert route.plug == Phoenix.LiveView.Plug
    assert route.log_module == AlgoieWeb.RepeatOrderReportLive
  end

  test "sales exports resolve to the tenant-authorized export controller" do
    for format <- ["pdf", "xlsx"] do
      route =
        Phoenix.Router.route_info(
          AlgoieWeb.Router,
          "GET",
          "/dashboard/reports/sales/export/#{format}",
          "demo.www.example.com"
        )

      assert route.plug == AlgoieWeb.SalesReportExportController
      assert route.plug_opts == :export
    end
  end

  test "store email settings resolve inside the tenant dashboard" do
    route =
      Phoenix.Router.route_info(
        AlgoieWeb.Router,
        "GET",
        "/dashboard/settings/email",
        "demo.www.example.com"
      )

    assert route.plug == Phoenix.LiveView.Plug
    assert route.log_module == AlgoieWeb.StoreEmailSettingsLive
  end
end
