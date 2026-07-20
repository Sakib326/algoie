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
    attribute(:cost_price, :decimal, constraints: [precision: 18, scale: 2])
    attribute(:barcode, :string)
    attribute(:stock, :integer, allow_nil?: false, default: 0)
    attribute(:reserved_quantity, :integer, allow_nil?: false, default: 0)
    attribute(:low_stock_threshold, :integer, allow_nil?: false, default: 10)
    attribute(:track_inventory?, :boolean, allow_nil?: false, default: true)
    attribute(:option_values, :map, default: %{})
    attribute(:position, :integer, allow_nil?: false, default: 0)
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
    has_many :product_images, Algoie.Products.ProductImage
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
        :cost_price,
        :barcode,
        :stock,
        :reserved_quantity,
        :low_stock_threshold,
        :track_inventory?,
        :option_values,
        :position
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

      validate(fn changeset, _context ->
        stock = Ash.Changeset.get_attribute(changeset, :stock)
        reserved = Ash.Changeset.get_attribute(changeset, :reserved_quantity)

        cond do
          stock && stock < 0 ->
            {:error, "stock cannot be negative"}

          reserved && reserved < 0 ->
            {:error, "reserved quantity cannot be negative"}

          stock && reserved && reserved > stock ->
            {:error, "reserved_quantity cannot exceed stock"}

          true ->
            :ok
        end
      end)

      validate(&validate_prices/2)
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :sku,
        :price,
        :compare_at_price,
        :cost_price,
        :barcode,
        :stock,
        :reserved_quantity,
        :low_stock_threshold,
        :track_inventory?,
        :option_values,
        :position
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

      validate(fn changeset, _context ->
        stock = Ash.Changeset.get_attribute(changeset, :stock)
        reserved = Ash.Changeset.get_attribute(changeset, :reserved_quantity)

        cond do
          stock && stock < 0 ->
            {:error, "stock cannot be negative"}

          reserved && reserved < 0 ->
            {:error, "reserved quantity cannot be negative"}

          stock && reserved && reserved > stock ->
            {:error, "reserved_quantity cannot exceed stock"}

          true ->
            :ok
        end
      end)

      validate(&validate_prices/2)
    end

    destroy :destroy do
      primary?(true)
      require_atomic?(false)
    end
  end

  @doc """
  Returns the computed stock status based on inventory fields.
  """
  def stock_status(%{track_inventory?: false}), do: :in_stock
  def stock_status(%{stock: stock}) when is_integer(stock) and stock > 0, do: :in_stock
  def stock_status(%{stock: _}), do: :out_of_stock
  def stock_status(_), do: :out_of_stock

  @doc """
  Returns true if stock is at or below the low stock threshold.
  """
  def low_stock?(%{track_inventory?: false}), do: false

  def low_stock?(%{stock: stock, low_stock_threshold: threshold})
      when is_integer(stock) and is_integer(threshold),
      do: stock <= threshold

  def low_stock?(_), do: false

  @doc """
  Returns available (non-reserved) stock.
  """
  def available_stock(%{stock: stock, reserved_quantity: reserved})
      when is_integer(stock) and is_integer(reserved),
      do: max(stock - reserved, 0)

  def available_stock(%{stock: stock}) when is_integer(stock), do: stock
  def available_stock(_), do: 0

  defp validate_prices(changeset, _context) do
    price = Ash.Changeset.get_attribute(changeset, :price)
    cost = Ash.Changeset.get_attribute(changeset, :cost_price)

    cond do
      price && Decimal.compare(price, Decimal.new(0)) != :gt ->
        {:error, "price must be greater than zero"}

      cost && Decimal.negative?(cost) ->
        {:error, "cost price cannot be negative"}

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
