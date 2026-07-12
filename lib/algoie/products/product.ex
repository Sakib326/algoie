defmodule Algoie.Products.Product do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("products")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:description, :string)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:brand_id, :uuid)
    attribute(:category_id, :uuid)

    attribute(:status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:draft, :active, :archived]],
      default: :draft
    )

    attribute(:images, {:array, :string}, default: [])
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :brand, Algoie.Products.Brand
    belongs_to :category, Algoie.Products.Category
    has_many :variants, Algoie.Products.Variant
    has_many :collection_products, Algoie.Products.CollectionProduct
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :description, :store_id, :brand_id, :category_id, :status, :images])
    end

    update :update do
      primary?(true)
      accept([:name, :description, :brand_id, :category_id, :status, :images])
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
