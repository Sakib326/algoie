defmodule Algoie.Customers.Coupon do
  use Ash.Resource,
    domain: Algoie.Customers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("coupons")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:code, :string, allow_nil?: false)
    attribute(:discount_type, :atom, allow_nil?: false, constraints: [one_of: [:percent, :fixed]])

    attribute(:discount_value, :decimal,
      allow_nil?: false,
      constraints: [precision: 18, scale: 2]
    )

    attribute(:min_order_value, :decimal, constraints: [precision: 18, scale: 2])
    attribute(:starts_at, :utc_datetime)
    attribute(:expires_at, :utc_datetime)
    attribute(:usage_limit, :integer)
    attribute(:times_used, :integer, allow_nil?: false, default: 0)
    attribute(:active?, :boolean, allow_nil?: false, default: true)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_coupon_code, [:store_id, :code])
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
        :code,
        :discount_type,
        :discount_value,
        :min_order_value,
        :starts_at,
        :expires_at,
        :usage_limit,
        :active?,
        :store_id
      ])

      change(&normalize_code/2)
      validate(&validate_coupon/2)
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :code,
        :discount_type,
        :discount_value,
        :min_order_value,
        :starts_at,
        :expires_at,
        :usage_limit,
        :active?
      ])

      change(&normalize_code/2)
      validate(&validate_coupon/2)
    end

    destroy(:destroy)
  end

  defp normalize_code(changeset, _context) do
    case Ash.Changeset.get_attribute(changeset, :code) do
      code when is_binary(code) ->
        Ash.Changeset.change_attribute(changeset, :code, code |> String.trim() |> String.upcase())

      _ ->
        changeset
    end
  end

  defp validate_coupon(changeset, _context) do
    type = Ash.Changeset.get_attribute(changeset, :discount_type)
    value = Ash.Changeset.get_attribute(changeset, :discount_value)
    minimum = Ash.Changeset.get_attribute(changeset, :min_order_value)
    limit = Ash.Changeset.get_attribute(changeset, :usage_limit)
    starts_at = Ash.Changeset.get_attribute(changeset, :starts_at)
    expires_at = Ash.Changeset.get_attribute(changeset, :expires_at)

    cond do
      value && Decimal.compare(value, Decimal.new(0)) != :gt ->
        {:error, "discount value must be greater than zero"}

      type == :percent && value && Decimal.compare(value, Decimal.new(100)) == :gt ->
        {:error, "percentage discount cannot exceed 100"}

      minimum && Decimal.negative?(minimum) ->
        {:error, "minimum order value cannot be negative"}

      limit && limit < 1 ->
        {:error, "usage limit must be at least 1"}

      starts_at && expires_at && DateTime.compare(expires_at, starts_at) != :gt ->
        {:error, "expiry must be after the start time"}

      true ->
        :ok
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
end
