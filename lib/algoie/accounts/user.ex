defmodule Algoie.Accounts.User do
  use Ash.Resource,
    domain: Algoie.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("users")
    repo(Algoie.Repo)
    schema("public")
  end

  authentication do
    session_identifier(:unsafe)

    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)
        confirmation_required?(false)
        sign_in_tokens_enabled?(true)
        register_action_accept([:name])
      end
    end

    tokens do
      enabled?(true)
      token_resource(Algoie.Accounts.Token)
      signing_algorithm("HS256")
      signing_secret(Application.compile_env(:algoie, :token_signing_secret, "dev-secret-change-in-prod"))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:email, :ci_string, allow_nil?: false, public?: true)
    attribute(:hashed_password, :string, allow_nil?: false, sensitive?: true)
    attribute(:name, :string)
    attribute(:default_tenant, :string)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_email, [:email])
  end

  relationships do
    has_many :store_staff_memberships, Algoie.Accounts.StoreStaff
  end

  actions do
    defaults([:read])

    update :update do
      primary?(true)
      accept([:email, :default_tenant])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action(:read) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if(Algoie.Policies.Checks.ActorIsRecordOwner)
      authorize_if expr(is_nil(actor))
    end

    policy action_type(:update) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if(Algoie.Policies.Checks.ActorIsRecordOwner)
    end
  end
end
