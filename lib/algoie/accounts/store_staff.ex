defmodule Algoie.Accounts.StoreStaff do
  @moduledoc """
  INTERNAL RESOURCE — links users to stores with a role.

  This resource uses raw user_id/store_id attributes (no foreign key constraints)
  because users are in the public schema while store_staff is in tenant schemas.
  """

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

    attribute(:user_id, :uuid, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
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
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end

    policy action_type(:read) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end

    policy action_type([:update, :destroy]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end
end
