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
    attribute(:delivery_charge_id, :uuid)
    attribute(:order_number, :string, allow_nil?: false)

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

    attribute(:subtotal_amount, :decimal,
      allow_nil?: false,
      default: Decimal.new(0),
      constraints: [precision: 18, scale: 2]
    )

    attribute(:discount_amount, :decimal,
      allow_nil?: false,
      default: Decimal.new(0),
      constraints: [precision: 18, scale: 2]
    )

    attribute(:shipping_amount, :decimal,
      allow_nil?: false,
      default: Decimal.new(0),
      constraints: [precision: 18, scale: 2]
    )

    attribute(:coupon_code, :string)
    attribute(:delivery_method, :string)
    attribute(:customer_name, :string, allow_nil?: false)
    attribute(:customer_email, :string)
    attribute(:customer_phone, :string)
    attribute(:shipping_address, :map, allow_nil?: false)
    attribute(:notes, :string)

    attribute(:payment_status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:pending, :paid, :failed, :refunded]],
      default: :pending
    )

    attribute(:fulfillment_status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:unfulfilled, :ready, :shipped, :delivered, :returned]],
      default: :unfulfilled
    )

    # Filled by a courier adapter later; keeping provider data isolated avoids
    # coupling the order lifecycle to any single courier API.
    attribute(:courier_provider, :string)
    attribute(:courier_consignment_id, :string)
    attribute(:tracking_code, :string)
    attribute(:courier_payload, :map, default: %{})

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :customer, Algoie.Customers.Customer, allow_nil?: false
    belongs_to :coupon, Algoie.Customers.Coupon
    belongs_to :delivery_charge, Algoie.Stores.DeliveryCharge
    has_many :line_items, Algoie.Orders.OrderLineItem, destination_attribute: :order_id
  end

  actions do
    read :read do
      primary?(true)
      pagination(offset?: true, default_limit: 12, countable: true, required?: false)
    end

    create :create do
      primary?(true)

      accept([
        :store_id,
        :customer_id,
        :coupon_id,
        :delivery_charge_id,
        :order_number,
        :status,
        :subtotal_amount,
        :discount_amount,
        :shipping_amount,
        :total_amount,
        :coupon_code,
        :delivery_method,
        :customer_name,
        :customer_email,
        :customer_phone,
        :shipping_address,
        :notes,
        :payment_status,
        :fulfillment_status,
        :courier_provider,
        :courier_consignment_id,
        :tracking_code,
        :courier_payload
      ])
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

    update :update_fulfillment do
      require_atomic?(false)

      accept([
        :fulfillment_status,
        :courier_provider,
        :courier_consignment_id,
        :tracking_code,
        :courier_payload
      ])
    end
  end

  identities do
    identity(:unique_order_number, [:store_id, :order_number])
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
