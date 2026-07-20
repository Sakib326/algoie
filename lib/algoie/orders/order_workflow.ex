defmodule Algoie.Orders.OrderWorkflow do
  @moduledoc """
  Transactional order creation. It resolves or creates the customer and address,
  snapshots all mutable display data, applies a coupon, and decrements stock.
  """

  import Ecto.Query
  require Ash.Query

  alias Algoie.Customers.{Coupon, Customer, CustomerAddress}
  alias Algoie.Orders.{Order, OrderLineItem}
  alias Algoie.Products.{Product, Variant}
  alias Algoie.Repo
  alias Algoie.Stores.DeliveryCharge

  def create_order(tenant, attrs, _actor) do
    Repo.transaction(fn ->
      with {:ok, customer} <- resolve_customer(tenant, attrs),
           {:ok, address} <- resolve_address(tenant, attrs, customer),
           {:ok, items, subtotal} <-
             resolve_items(tenant, attrs.store_id, attrs.variant_quantities),
           {:ok, coupon} <- resolve_coupon(tenant, attrs.store_id, attrs[:coupon_code], subtotal),
           discount =
             if(coupon, do: Algoie.Customers.discount_for(coupon, subtotal), else: Decimal.new(0)),
           {:ok, delivery} <-
             resolve_delivery_charge(tenant, attrs.store_id, attrs[:delivery_charge_id], subtotal),
           shipping = delivery.amount,
           total =
             subtotal
             |> Decimal.sub(discount)
             |> Decimal.add(shipping)
             |> Decimal.max(Decimal.new(0)),
           {:ok, :ok} <- decrement_stock(tenant, attrs.store_id, items),
           {:ok, order} <-
             create_order_record(
               tenant,
               attrs,
               customer,
               address,
               coupon,
               delivery,
               subtotal,
               discount,
               shipping,
               total
             ),
           {:ok, :ok} <- create_line_items(tenant, order, items),
           {:ok, :ok} <- increment_coupon_usage(tenant, coupon) do
        order
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp resolve_customer(tenant, %{customer_id: id}) when is_binary(id) and id != "" do
    case Ash.get(Customer, id, tenant: tenant, authorize?: false) do
      {:ok, customer} -> {:ok, customer}
      _ -> {:error, :customer_not_found}
    end
  end

  defp resolve_customer(tenant, attrs) do
    details = attrs.customer
    email = blank_to_nil(details[:email])
    phone = blank_to_nil(details[:phone])

    existing =
      cond do
        email -> find_customer(tenant, attrs.store_id, :email, email)
        phone -> find_customer(tenant, attrs.store_id, :phone, phone)
        true -> nil
      end

    if existing do
      {:ok, existing}
    else
      Customer
      |> Ash.Changeset.for_create(
        :create,
        %{
          store_id: attrs.store_id,
          name: details[:name],
          email: email,
          phone: phone
        },
        tenant: tenant
      )
      |> Ash.create(authorize?: false)
    end
  end

  defp find_customer(tenant, store_id, :email, value) do
    Customer
    |> Ash.Query.filter(store_id == ^store_id and email == ^value)
    |> Ash.read_one!(tenant: tenant, authorize?: false)
  end

  defp find_customer(tenant, store_id, :phone, value) do
    Customer
    |> Ash.Query.filter(store_id == ^store_id and phone == ^value)
    |> Ash.read_one!(tenant: tenant, authorize?: false)
  end

  defp resolve_address(tenant, %{address_id: id}, _customer) when is_binary(id) and id != "" do
    case Ash.get(CustomerAddress, id, tenant: tenant, authorize?: false) do
      {:ok, address} -> {:ok, address}
      _ -> {:error, :address_not_found}
    end
  end

  defp resolve_address(tenant, attrs, customer) do
    address = attrs.address

    CustomerAddress
    |> Ash.Changeset.for_create(
      :create,
      %{
        customer_id: customer.id,
        store_id: attrs.store_id,
        label: blank_to_nil(address[:label]) || "Delivery address",
        recipient_name: blank_to_nil(address[:recipient_name]) || customer.name,
        phone: blank_to_nil(address[:phone]) || customer.phone,
        address_line1: address[:address_line1],
        address_line2: blank_to_nil(address[:address_line2]),
        city: address[:city],
        area: blank_to_nil(address[:area]),
        postal_code: blank_to_nil(address[:postal_code]),
        country: blank_to_nil(address[:country]) || "Bangladesh",
        default?: address[:default?] in [true, "true"]
      },
      tenant: tenant
    )
    |> Ash.create(authorize?: false)
  end

  defp resolve_items(tenant, store_id, quantities)
       when is_list(quantities) and quantities != [] do
    Enum.reduce_while(quantities, {:ok, [], Decimal.new(0)}, fn entry, {:ok, items, subtotal} ->
      quantity = entry.quantity

      result =
        Variant
        |> Ash.Query.filter(id == ^entry.variant_id and store_id == ^store_id)
        |> Ash.read_one(tenant: tenant, authorize?: false)

      case result do
        {:ok, variant} when quantity > 0 ->
          case Ash.get(Product, variant.product_id, tenant: tenant, authorize?: false) do
            {:ok, %Product{status: :active} = product} ->
              available =
                if variant.track_inventory?,
                  do: variant.stock - variant.reserved_quantity,
                  else: quantity

              if available >= quantity do
                variant = Map.put(variant, :product, product)
                item = %{variant: variant, quantity: quantity}
                line_total = Decimal.mult(variant.price, Decimal.new(quantity))
                {:cont, {:ok, [item | items], Decimal.add(subtotal, line_total)}}
              else
                {:halt, {:error, {:insufficient_stock, variant.sku}}}
              end

            _ ->
              {:halt, {:error, :inactive_product}}
          end

        {:ok, _} ->
          {:halt, {:error, :invalid_quantity}}

        _ ->
          {:halt, {:error, :variant_not_found}}
      end
    end)
    |> case do
      {:ok, items, subtotal} -> {:ok, Enum.reverse(items), subtotal}
      error -> error
    end
  end

  defp resolve_items(_tenant, _store_id, _quantities), do: {:error, :order_requires_items}

  defp resolve_coupon(_tenant, _store_id, code, _subtotal) when code in [nil, ""], do: {:ok, nil}

  defp resolve_coupon(tenant, store_id, code, subtotal) do
    normalized = code |> String.trim() |> String.upcase()

    result =
      Coupon
      |> Ash.Query.filter(code == ^normalized and store_id == ^store_id)
      |> Ash.read_one(tenant: tenant, authorize?: false)

    case result do
      {:ok, coupon} ->
        if Algoie.Customers.coupon_valid_for_use?(coupon, subtotal),
          do: {:ok, coupon},
          else: {:error, :coupon_not_valid_for_order}

      _ ->
        {:error, :coupon_not_found}
    end
  end

  defp resolve_delivery_charge(_tenant, _store_id, id, _subtotal) when id in [nil, ""],
    do: {:ok, %{id: nil, name: nil, amount: Decimal.new(0)}}

  defp resolve_delivery_charge(tenant, store_id, id, subtotal) do
    result =
      DeliveryCharge
      |> Ash.Query.filter(id == ^id and store_id == ^store_id and active? == true)
      |> Ash.read_one(tenant: tenant, authorize?: false)

    case result do
      {:ok, rate} ->
        free? =
          rate.free_delivery_threshold &&
            Decimal.compare(subtotal, rate.free_delivery_threshold) != :lt

        amount = if(free?, do: Decimal.new(0), else: rate.charge)
        {:ok, %{id: rate.id, name: rate.name, amount: amount}}

      _ ->
        {:error, :delivery_rate_not_found}
    end
  end

  defp decrement_stock(tenant, store_id, items) do
    Enum.reduce_while(items, {:ok, :ok}, fn %{variant: variant, quantity: quantity}, _acc ->
      if variant.track_inventory? do
        record =
          from(v in Variant,
            where:
              v.id == ^Ecto.UUID.dump!(variant.id) and v.store_id == ^Ecto.UUID.dump!(store_id),
            lock: "FOR UPDATE"
          )
          |> Repo.one(prefix: tenant)

        if record && record.stock - record.reserved_quantity >= quantity do
          record
          |> Ecto.Changeset.change(stock: record.stock - quantity)
          |> Repo.update!(prefix: tenant)

          {:cont, {:ok, :ok}}
        else
          {:halt, {:error, {:insufficient_stock, variant.sku}}}
        end
      else
        {:cont, {:ok, :ok}}
      end
    end)
  end

  defp create_order_record(
         tenant,
         attrs,
         customer,
         address,
         coupon,
         delivery,
         subtotal,
         discount,
         shipping,
         total
       ) do
    Order
    |> Ash.Changeset.for_create(
      :create,
      %{
        store_id: attrs.store_id,
        customer_id: customer.id,
        coupon_id: coupon && coupon.id,
        delivery_charge_id: delivery.id,
        order_number: order_number(),
        status: :pending,
        subtotal_amount: subtotal,
        discount_amount: discount,
        shipping_amount: shipping,
        total_amount: total,
        coupon_code: coupon && coupon.code,
        delivery_method: delivery.name,
        customer_name: customer.name,
        customer_email: customer.email,
        customer_phone: customer.phone,
        shipping_address: address_snapshot(address),
        notes: blank_to_nil(attrs[:notes])
      },
      tenant: tenant
    )
    |> Ash.create(authorize?: false)
  end

  defp create_line_items(tenant, order, items) do
    Enum.reduce_while(items, {:ok, :ok}, fn %{variant: variant, quantity: quantity}, _acc ->
      variant_name =
        variant.option_values
        |> Enum.map_join(" / ", fn {key, value} -> "#{key}: #{value}" end)
        |> blank_to_nil()

      result =
        OrderLineItem
        |> Ash.Changeset.for_create(
          :create,
          %{
            order_id: order.id,
            variant_id: variant.id,
            quantity: quantity,
            unit_price: variant.price,
            product_name: variant.product.name,
            variant_name: variant_name,
            sku: variant.sku
          },
          tenant: tenant
        )
        |> Ash.create(authorize?: false)

      case result do
        {:ok, _} -> {:cont, {:ok, :ok}}
        error -> {:halt, error}
      end
    end)
  end

  defp increment_coupon_usage(_tenant, nil), do: {:ok, :ok}

  defp increment_coupon_usage(tenant, coupon) do
    coupon
    |> Ecto.Changeset.change(times_used: coupon.times_used + 1)
    |> Repo.update!(prefix: tenant)

    {:ok, :ok}
  end

  defp address_snapshot(address) do
    Map.take(address, [
      :label,
      :recipient_name,
      :phone,
      :address_line1,
      :address_line2,
      :city,
      :area,
      :postal_code,
      :country
    ])
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: String.trim(value) |> then(&if(&1 == "", do: nil, else: &1))

  defp blank_to_nil(value), do: value

  defp order_number do
    suffix =
      Ecto.UUID.generate() |> String.replace("-", "") |> String.slice(0, 6) |> String.upcase()

    "ORD-#{Date.utc_today() |> Calendar.strftime("%y%m%d")}-#{suffix}"
  end
end
