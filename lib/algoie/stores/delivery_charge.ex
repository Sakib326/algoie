defmodule Algoie.Stores.DeliveryCharge do
  use Ash.Resource,
    domain: Algoie.Stores,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("delivery_charges")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:name, :string, allow_nil?: false)
    attribute(:city, :string)
    attribute(:area, :string)
    attribute(:charge, :decimal, allow_nil?: false, constraints: [precision: 18, scale: 2])
    attribute(:free_delivery_threshold, :decimal, constraints: [precision: 18, scale: 2])
    attribute(:estimated_days_min, :integer, allow_nil?: false, default: 1)
    attribute(:estimated_days_max, :integer, allow_nil?: false, default: 3)
    attribute(:priority, :integer, allow_nil?: false, default: 0)
    attribute(:active?, :boolean, allow_nil?: false, default: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_delivery_charge_name, [:store_id, :name])
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :orders, Algoie.Orders.Order
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :store_id,
        :name,
        :city,
        :area,
        :charge,
        :free_delivery_threshold,
        :estimated_days_min,
        :estimated_days_max,
        :priority,
        :active?
      ])

      validate(&validate_rate/2)
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :name,
        :city,
        :area,
        :charge,
        :free_delivery_threshold,
        :estimated_days_min,
        :estimated_days_max,
        :priority,
        :active?
      ])

      validate(&validate_rate/2)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  defp validate_rate(changeset, _context) do
    charge = Ash.Changeset.get_attribute(changeset, :charge)
    threshold = Ash.Changeset.get_attribute(changeset, :free_delivery_threshold)
    minimum = Ash.Changeset.get_attribute(changeset, :estimated_days_min)
    maximum = Ash.Changeset.get_attribute(changeset, :estimated_days_max)

    cond do
      charge && Decimal.negative?(charge) ->
        {:error, field: :charge, message: "cannot be negative"}

      threshold && Decimal.negative?(threshold) ->
        {:error, field: :free_delivery_threshold, message: "cannot be negative"}

      minimum && minimum < 0 ->
        {:error, field: :estimated_days_min, message: "cannot be negative"}

      minimum && maximum && maximum < minimum ->
        {:error, field: :estimated_days_max, message: "must be at least the minimum"}

      true ->
        :ok
    end
  end

  policies do
    policy action_type([:create, :read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "discounts"})
    end

    policy action_type(:destroy) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end
end
