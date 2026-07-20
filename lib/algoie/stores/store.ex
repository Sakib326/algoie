defmodule Algoie.Stores.Store do
  use Ash.Resource,
    domain: Algoie.Stores,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins, only: [cascade_destroy: 2, after_action: 1]

  postgres do
    table("stores")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:slug, :string, allow_nil?: false)
    attribute(:custom_domain, :string)
    attribute(:email, :string)
    attribute(:phone, :string)
    attribute(:address, :string)
    attribute(:city, :string)
    attribute(:country, :string, allow_nil?: false, default: "Bangladesh")
    attribute(:currency, :string, allow_nil?: false, default: "BDT")
    attribute(:logo_url, :string)
    attribute(:invoice_prefix, :string, allow_nil?: false, default: "INV")

    attribute(:status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:active, :inactive]],
      default: :active
    )

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  relationships do
    has_many :staff_memberships, Algoie.Accounts.StoreStaff
    has_many :delivery_charges, Algoie.Stores.DeliveryCharge
  end

  actions do
    read :read do
      primary?(true)
    end

    create :create do
      primary?(true)

      accept([
        :name,
        :slug,
        :custom_domain,
        :status,
        :email,
        :phone,
        :address,
        :city,
        :country,
        :currency,
        :logo_url,
        :invoice_prefix
      ])

      change(
        after_action(fn _changeset, store, _context ->
          case Algoie.Stores.create_registry_entry(store) do
            :ok -> {:ok, store}
            {:error, error} -> {:error, error}
          end
        end)
      )
    end

    update :update do
      require_atomic?(false)

      accept([
        :name,
        :slug,
        :custom_domain,
        :status,
        :email,
        :phone,
        :address,
        :city,
        :country,
        :currency,
        :logo_url,
        :invoice_prefix
      ])

      change(
        after_action(fn _changeset, store, _context ->
          case Algoie.Stores.update_registry_entry(store) do
            :ok -> {:ok, store}
            {:error, error} -> {:error, error}
          end
        end)
      )
    end

    destroy :destroy do
      primary?(true)
      require_atomic?(false)
      change(cascade_destroy(:staff_memberships, after_action?: false))
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type([:read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "settings"})
    end

    policy action_type(:destroy) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end
end
