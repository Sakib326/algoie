defmodule Algoie.Orders.OrderLineItem do
  use Ash.Resource,
    domain: Algoie.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Policy.Check.Builtins, only: [always: 0]

  postgres do
    table("order_line_items")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:order_id, :uuid, allow_nil?: false)
    attribute(:variant_id, :uuid, allow_nil?: false)
    attribute(:quantity, :integer, allow_nil?: false)
    attribute(:unit_price, :decimal, allow_nil?: false, constraints: [precision: 18, scale: 2])
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :order, Algoie.Orders.Order, allow_nil?: false
    belongs_to :variant, Algoie.Products.Variant, allow_nil?: false
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:order_id, :variant_id, :quantity, :unit_price])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
