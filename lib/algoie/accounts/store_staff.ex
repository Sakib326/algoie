defmodule Algoie.Accounts.StoreStaff do
  use Ash.Resource,
    domain: Algoie.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("store_staff")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:role, :atom,
      allow_nil?: false,
      constraints: [one_of: [:owner, :staff]]
    )

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :user, Algoie.Accounts.User, allow_nil?: false
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
  end

  identities do
    identity(:unique_user_store, [:user_id, :store_id])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:role, :user_id, :store_id])
    end

    update :update do
      accept([:role])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end
end
