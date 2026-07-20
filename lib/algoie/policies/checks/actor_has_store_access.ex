defmodule Algoie.Policies.Checks.ActorHasStoreAccess do
  @moduledoc """
  Policy check that verifies access and restricts records to the active store.

  Looks up the StoreStaff row for (actor.id, store_id) and compares role.
  Uses Ash.read_one with authorize?: false to avoid circular authorization.

  The routing plug must set both:
  - context[:tenant] — the Tenant ID (for schema routing)
  - context[:store_id] — the Store ID (for this policy check)
  """

  use Ash.Policy.FilterCheck

  alias Algoie.Accounts.StoreStaff
  require Ash.Query

  @impl true
  def describe(opts) do
    required =
      Keyword.get(opts, :permission) || Keyword.get(opts, :area) ||
        Keyword.get(opts, :level, :staff)

    "actor has #{required} access to the store"
  end

  @impl true
  def filter(actor, authorizer, opts) do
    required_level = Keyword.get(opts, :level)
    required_permission = Keyword.get(opts, :permission)
    area = Keyword.get(opts, :area)
    required_permission = required_permission || area_permission(area, authorizer.action.type)

    store_id = authorizer.context[:store_id]
    tenant_id = authorizer.context[:tenant]

    allowed? =
      with store_id when not is_nil(store_id) <- store_id,
           tenant_id when not is_nil(tenant_id) <- tenant_id,
           membership when not is_nil(membership) <-
             get_store_staff_membership(actor, store_id, tenant_id) do
        membership_allowed?(membership, required_level, required_permission)
      else
        _ -> false
      end

    if allowed?, do: store_filter(authorizer.resource, store_id), else: expr(false)
  end

  defp membership_allowed?(%{role: :owner}, _required_level, _required_permission), do: true
  defp membership_allowed?(%{role: :staff}, :owner, _required_permission), do: false

  defp membership_allowed?(%{role: role, permissions: permissions}, _level, permission)
       when is_binary(permission) do
    Algoie.Accounts.StorePermissions.allowed?(role, permissions, permission)
  end

  defp membership_allowed?(%{role: :staff}, level, nil) when level in [:staff, nil], do: true
  defp membership_allowed?(_membership, _level, _permission), do: false

  defp store_filter(Algoie.Stores.Store, store_id), do: expr(id == ^store_id)

  defp store_filter(Algoie.Products.ProductImage, store_id),
    do: expr(product.store_id == ^store_id and media_asset.store_id == ^store_id)

  defp store_filter(Algoie.Products.ProductCategory, store_id),
    do: expr(product.store_id == ^store_id and category.store_id == ^store_id)

  defp store_filter(Algoie.Products.ProductTag, store_id),
    do: expr(product.store_id == ^store_id and tag.store_id == ^store_id)

  defp store_filter(Algoie.Products.CollectionProduct, store_id),
    do: expr(product.store_id == ^store_id and collection.store_id == ^store_id)

  defp store_filter(Algoie.Orders.OrderLineItem, store_id),
    do: expr(order.store_id == ^store_id and variant.store_id == ^store_id)

  defp store_filter(_resource, store_id), do: expr(store_id == ^store_id)

  defp area_permission(nil, _action_type), do: nil
  defp area_permission(area, :read), do: "#{area}.view"
  defp area_permission(area, _action_type), do: "#{area}.manage"

  defp get_store_staff_membership(nil, _store_id, _tenant_id), do: nil

  defp get_store_staff_membership(actor, store_id, tenant_id) do
    StoreStaff
    |> Ash.Query.filter(user_id == ^actor.id and store_id == ^store_id)
    |> Ash.read_one(tenant: tenant_id, authorize?: false)
    |> case do
      {:ok, membership} when not is_nil(membership) ->
        Map.take(membership, [:role, :permissions])

      _ ->
        nil
    end
  end
end
