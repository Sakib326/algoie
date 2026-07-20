defmodule Algoie.Accounts.TenantMembership do
  @moduledoc "Links a global user to a tenant-level administration role."

  use Ash.Resource,
    domain: Algoie.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("tenant_memberships")
    repo(Algoie.Repo)
    schema("public")
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:tenant_id, :uuid, allow_nil?: false)
    attribute(:user_id, :uuid, allow_nil?: false)

    attribute(:role, :atom,
      allow_nil?: false,
      default: :member,
      constraints: [one_of: [:owner, :admin, :member]]
    )

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_tenant_user, [:tenant_id, :user_id])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:tenant_id, :user_id, :role])
    end

    update :update do
      primary?(true)
      accept([:role])
    end
  end

  policies do
    policy always() do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end
  end
end
