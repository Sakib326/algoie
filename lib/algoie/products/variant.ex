defmodule Algoie.Products.Variant do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("variants")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:product_id, :uuid, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:sku, :string, allow_nil?: false)
    attribute(:price, :decimal, allow_nil?: false, constraints: [precision: 18, scale: 2])
    attribute(:compare_at_price, :decimal, constraints: [precision: 18, scale: 2])
    attribute(:stock, :integer, allow_nil?: false, default: 0)
    attribute(:track_inventory?, :boolean, allow_nil?: false, default: true)
    attribute(:option_values, :map, default: %{})
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_sku, [:store_id, :sku])
  end

  relationships do
    belongs_to :product, Algoie.Products.Product, allow_nil?: false
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :order_line_items, Algoie.Orders.OrderLineItem
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :product_id,
        :store_id,
        :sku,
        :price,
        :compare_at_price,
        :stock,
        :track_inventory?,
        :option_values
      ])

      validate(fn changeset, _context ->
        price = Ash.Changeset.get_attribute(changeset, :price)
        compare_at = Ash.Changeset.get_attribute(changeset, :compare_at_price)

        if compare_at && price && Decimal.compare(compare_at, price) != :gt do
          {:error, "compare_at_price must be greater than price"}
        else
          :ok
        end
      end)
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:sku, :price, :compare_at_price, :stock, :track_inventory?, :option_values])

      validate(fn changeset, _context ->
        price = Ash.Changeset.get_attribute(changeset, :price)
        compare_at = Ash.Changeset.get_attribute(changeset, :compare_at_price)

        if compare_at && price && Decimal.compare(compare_at, price) != :gt do
          {:error, "compare_at_price must be greater than price"}
        else
          :ok
        end
      end)
    end

    destroy :destroy do
      primary?(true)
      require_atomic?(false)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
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
