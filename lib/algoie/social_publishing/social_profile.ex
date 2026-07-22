defmodule Algoie.SocialPublishing.SocialProfile do
  use Ash.Resource,
    domain: Algoie.SocialPublishing.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("social_profiles")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:provider_profile_id, :string, allow_nil?: false)
    attribute(:name, :string, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :accounts, Algoie.SocialPublishing.SocialAccount
  end

  identities do
    identity(:unique_store, [:store_id])
    identity(:unique_provider_profile, [:provider_profile_id])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:store_id, :provider_profile_id, :name])
    end

    update :update do
      primary?(true)
      accept([:name, :provider_profile_id])
    end
  end

  policies do
    policy action_type([:read, :create, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "settings"})
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "social"})
    end
  end
end
