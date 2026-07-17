defmodule Algoie.Products.ProductImage do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("product_images")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:product_id, :uuid, allow_nil?: false)
    attribute(:variant_id, :uuid)
    attribute(:media_asset_id, :uuid, allow_nil?: false)
    attribute(:alt_text, :string)
    attribute(:position, :integer, allow_nil?: false, default: 0)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :product, Algoie.Products.Product, allow_nil?: false
    belongs_to :variant, Algoie.Products.Variant
    belongs_to :media_asset, Algoie.Media.MediaAsset, allow_nil?: false
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:product_id, :variant_id, :media_asset_id, :alt_text, :position])
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:alt_text, :position, :variant_id])
    end

    destroy :destroy do
      primary?(true)
      require_atomic?(false)
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
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end
  end
end
