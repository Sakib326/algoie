defmodule Algoie.Accounts.Tenant do
  use Ash.Resource,
    domain: Algoie.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("tenants")
    repo(Algoie.Repo)
    schema("public")
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:owner_email, :ci_string, allow_nil?: false)

    attribute(:billing_status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:trial, :active, :suspended]],
      default: :trial
    )

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_owner_email, [:owner_email])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :owner_email, :billing_status])
    end

    update :update do
      accept([:name, :owner_email, :billing_status])
    end

    destroy(:destroy)
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end
  end
end
