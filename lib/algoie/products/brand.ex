defmodule Algoie.Products.Brand do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("brands")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :products, Algoie.Products.Product
  end

  actions do
    read :read do
      primary?(true)
      pagination offset?: true, default_limit: 12, countable: true, required?: false
    end

    create :create do
      primary?(true)
      accept([:name, :store_id])
    end

    update :update do
      primary?(true)
      accept([:name])
    end

    destroy :destroy do
      primary?(true)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
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
