defmodule Algoie.Customers.Customer do
  use Ash.Resource,
    domain: Algoie.Customers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("customers")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:email, :ci_string)
    attribute(:phone, :string)
    attribute(:hashed_password, :string, sensitive?: true)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_customer_email, [:store_id, :email])
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :orders, Algoie.Orders.Order
    has_many :addresses, Algoie.Customers.CustomerAddress
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :email, :phone, :store_id])
    end

    create :register do
      accept([:name, :email, :phone, :store_id])
      argument(:password, :string, allow_nil?: false, sensitive?: true)
      change(&hash_password/2)
    end

    update :update do
      primary?(true)
      accept([:name, :email, :phone])
    end

    update :register_existing do
      require_atomic?(false)
      accept([:name, :phone])
      argument(:password, :string, allow_nil?: false, sensitive?: true)

      validate(fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :hashed_password),
          do: {:error, "An account already exists for this email"},
          else: :ok
      end)

      change(&hash_password/2)
    end

    update :update_account do
      accept([:name, :phone])
    end

    update :reset_password do
      require_atomic?(false)
      argument(:password, :string, allow_nil?: false, sensitive?: true)
      change(&hash_password/2)
    end

    destroy :destroy do
      primary?(true)
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
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end

  defp hash_password(changeset, _context) do
    password = Ash.Changeset.get_argument(changeset, :password) || ""

    if String.length(password) >= 8 do
      Ash.Changeset.force_change_attribute(
        changeset,
        :hashed_password,
        Bcrypt.hash_pwd_salt(password)
      )
    else
      Ash.Changeset.add_error(changeset,
        field: :password,
        message: "must be at least 8 characters"
      )
    end
  end
end
