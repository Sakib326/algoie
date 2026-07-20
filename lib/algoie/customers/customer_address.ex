defmodule Algoie.Customers.CustomerAddress do
  use Ash.Resource,
    domain: Algoie.Customers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("customer_addresses")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:customer_id, :uuid, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:label, :string, default: "Delivery address")
    attribute(:recipient_name, :string, allow_nil?: false)
    attribute(:phone, :string, allow_nil?: false)
    attribute(:address_line1, :string, allow_nil?: false)
    attribute(:address_line2, :string)
    attribute(:city, :string, allow_nil?: false)
    attribute(:area, :string)
    attribute(:postal_code, :string)
    attribute(:country, :string, allow_nil?: false, default: "Bangladesh")
    attribute(:default?, :boolean, allow_nil?: false, default: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, Algoie.Customers.Customer, allow_nil?: false
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :customer_id,
        :store_id,
        :label,
        :recipient_name,
        :phone,
        :address_line1,
        :address_line2,
        :city,
        :area,
        :postal_code,
        :country,
        :default?
      ])
    end

    update :update do
      primary?(true)

      accept([
        :label,
        :recipient_name,
        :phone,
        :address_line1,
        :address_line2,
        :city,
        :area,
        :postal_code,
        :country,
        :default?
      ])
    end
  end

  policies do
    policy action_type([:create, :read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end
  end
end
