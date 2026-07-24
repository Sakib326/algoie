defmodule Algoie.SocialPublishing.SocialAccount do
  use Ash.Resource,
    domain: Algoie.SocialPublishing.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("social_accounts")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  @platforms ~w(facebook instagram whatsapp tiktok metaads)

  def platforms, do: @platforms

  attributes do
    uuid_primary_key(:id)
    attribute(:social_profile_id, :uuid, allow_nil?: false)
    attribute(:provider_account_id, :string, allow_nil?: false)

    attribute(:platform, :atom,
      allow_nil?: false,
      constraints: [one_of: Enum.map(@platforms, &String.to_atom/1)]
    )

    attribute(:status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:connected, :disconnected, :needs_reauth]],
      default: :connected
    )

    attribute(:metadata, :map, default: %{})
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :social_profile, Algoie.SocialPublishing.SocialProfile, allow_nil?: false
  end

  identities do
    identity(:unique_provider_account, [:provider_account_id])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:social_profile_id, :provider_account_id, :platform, :status, :metadata])
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:platform, :status, :metadata, :social_profile_id])
    end

    destroy :destroy do
      primary?(true)
    end
  end

  policies do
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "settings"})
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "social"})
    end
  end
end
