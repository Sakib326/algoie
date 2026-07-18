defmodule Algoie.Orders.Order do
  use Ash.Resource,
    domain: Algoie.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("orders")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:customer_id, :uuid, allow_nil?: false)
    attribute(:coupon_id, :uuid)

    attribute(:status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:pending, :pre_order, :confirmed, :fulfilled, :cancelled]],
      default: :pending
    )

    attribute(:total_amount, :decimal,
      allow_nil?: false,
      default: Decimal.new(0),
      constraints: [precision: 18, scale: 2]
    )

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :customer, Algoie.Customers.Customer, allow_nil?: false
    belongs_to :coupon, Algoie.Customers.Coupon
    has_many :line_items, Algoie.Orders.OrderLineItem, destination_attribute: :order_id
  end

  actions do
    read :read do
      primary?(true)
      pagination offset?: true, default_limit: 12, countable: true
    end

    create :create do
      primary?(true)
      accept([:store_id, :customer_id, :coupon_id, :status, :total_amount])
    end

    update :update_status do
      primary?(true)
      require_atomic?(false)
      accept([:status])

      validate(fn changeset, _context ->
        current = Ash.Changeset.get_data(changeset, :status)
        new_status = Ash.Changeset.get_attribute(changeset, :status)

        if current == new_status do
          :ok
        else
          allowed = allowed_transitions(current)

          if new_status in allowed do
            :ok
          else
            {:error, "cannot transition from #{current} to #{new_status}"}
          end
        end
      end)
    end
  end

  defp allowed_transitions(:pending), do: [:pre_order, :confirmed, :cancelled]
  defp allowed_transitions(:pre_order), do: [:confirmed, :cancelled]
  defp allowed_transitions(:confirmed), do: [:fulfilled, :cancelled]
  defp allowed_transitions(:fulfilled), do: []
  defp allowed_transitions(:cancelled), do: []
  defp allowed_transitions(_), do: []

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
    end

    policy action_type([:read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end
  end
end
