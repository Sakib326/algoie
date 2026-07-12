defmodule Algoie.Customers.Coupon do
  use Ash.Resource,
    domain: Algoie.Customers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("coupons")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:code, :string, allow_nil?: false)
    attribute(:discount_type, :atom, allow_nil?: false, constraints: [one_of: [:percent, :fixed]])

    attribute(:discount_value, :decimal,
      allow_nil?: false,
      constraints: [precision: 18, scale: 2]
    )

    attribute(:min_order_value, :decimal, constraints: [precision: 18, scale: 2])
    attribute(:starts_at, :utc_datetime)
    attribute(:expires_at, :utc_datetime)
    attribute(:usage_limit, :integer)
    attribute(:times_used, :integer, allow_nil?: false, default: 0)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_coupon_code, [:store_id, :code])
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :orders, Algoie.Orders.Order
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :code,
        :discount_type,
        :discount_value,
        :min_order_value,
        :starts_at,
        :expires_at,
        :usage_limit,
        :store_id
      ])
    end

    update :update do
      primary?(true)

      accept([
        :code,
        :discount_type,
        :discount_value,
        :min_order_value,
        :starts_at,
        :expires_at,
        :usage_limit
      ])
    end

    destroy(:destroy)
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type([:read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end

    policy action_type(:destroy) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end
end
