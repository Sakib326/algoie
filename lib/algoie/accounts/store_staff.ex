defmodule Algoie.Accounts.StoreStaff do
  @moduledoc """
  INTERNAL RESOURCE.

  This resource is used internally for permission resolution,
  tenant provisioning, and cascade operations.

  It is NOT intended to be exposed directly through APIs.

  If StoreStaff becomes an API-facing resource (staff invitations,
  role management, staff listing, etc.), the current `always()`
  policies MUST be replaced with explicit authorization rules.
  """

  use Ash.Resource,
    domain: Algoie.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Policy.Check.Builtins, only: [always: 0]

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

    # Read policy: always allow (schema-level isolation via Ash multitenancy handles tenant separation)
    policy action_type(:read) do
      authorize_if(always())
    end

    # Update/destroy policy: always allow within tenant (parent Store policy controls access)
    policy action_type([:update, :destroy]) do
      authorize_if(always())
    end
  end
end
