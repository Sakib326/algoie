defmodule Algoie.Accounts.StorePermissions do
  @moduledoc """
  Defines granular permissions for a user's membership in one store.

  Owners always have every permission. Staff access is deny-by-default: a nil
  or empty permission list grants no module access, and only explicitly saved
  permissions are granted.
  """

  @permissions [
    {"catalog.view", "View catalog"},
    {"catalog.manage", "Manage catalog"},
    {"inventory.view", "View inventory"},
    {"inventory.manage", "Manage inventory"},
    {"orders.view", "View orders"},
    {"orders.manage", "Manage orders"},
    {"customers.view", "View customers"},
    {"customers.manage", "Manage customers"},
    {"discounts.view", "View discounts and delivery rates"},
    {"discounts.manage", "Manage discounts and delivery rates"},
    {"reports.view", "View and export reports"},
    {"engagement.view", "View conversations and campaigns"},
    {"engagement.manage", "Manage conversations and campaigns"},
    {"ai.use", "Use the AI assistant"},
    {"settings.view", "View store settings"},
    {"settings.manage", "Manage store settings"},
    {"team.view", "View team members"},
    {"team.manage", "Manage team members and access"}
  ]

  @all Enum.map(@permissions, &elem(&1, 0))
  def all, do: @permissions
  def keys, do: @all
  def defaults(:owner), do: @all
  def defaults(:staff), do: []
  def defaults(_), do: []

  def effective(:owner, _permissions), do: @all
  def effective(:staff, nil), do: []
  def effective(:staff, permissions) when is_list(permissions), do: valid(permissions)
  def effective(_, _), do: []

  def allowed?(role, permissions, required) when is_atom(required),
    do: allowed?(role, permissions, Atom.to_string(required))

  def allowed?(role, permissions, required) when is_binary(required) do
    role == :owner or required in effective(role, permissions)
  end

  def valid(permissions) when is_list(permissions),
    do: Enum.filter(@all, &(&1 in permissions))

  def valid(_), do: []
end
