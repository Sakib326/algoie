defmodule Algoie.Products.ProductCategory do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Policy.Check.Builtins, only: [always: 0]

  postgres do
    table("product_categories")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:product_id, :uuid, allow_nil?: false)
    attribute(:category_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_product_category, [:product_id, :category_id])
  end

  relationships do
    belongs_to :product, Algoie.Products.Product, allow_nil?: false
    belongs_to :category, Algoie.Products.Category, allow_nil?: false
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:product_id, :category_id])
    end

    destroy(:destroy)
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:destroy) do
      authorize_if(always())
    end
  end
end
