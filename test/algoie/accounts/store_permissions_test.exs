defmodule Algoie.Accounts.StorePermissionsTest do
  use ExUnit.Case, async: true

  alias Algoie.Accounts.StorePermissions

  test "owners always receive every permission" do
    assert StorePermissions.effective(:owner, []) == StorePermissions.keys()
    assert StorePermissions.allowed?(:owner, [], "team.manage")
  end

  test "staff memberships without assigned permissions have no access" do
    refute StorePermissions.allowed?(:staff, nil, "orders.manage")
    refute StorePermissions.allowed?(:staff, nil, "reports.view")
    refute StorePermissions.allowed?(:staff, nil, "customers.view")
    refute StorePermissions.allowed?(:staff, nil, "settings.manage")
    refute StorePermissions.allowed?(:staff, nil, "team.manage")
  end

  test "explicit staff permissions are restrictive and discard unknown values" do
    permissions = StorePermissions.valid(["orders.view", "not-a-real-permission"])

    assert permissions == ["orders.view"]
    assert StorePermissions.allowed?(:staff, permissions, "orders.view")
    refute StorePermissions.allowed?(:staff, permissions, "orders.manage")
    refute StorePermissions.allowed?(:staff, permissions, "catalog.view")
  end
end
