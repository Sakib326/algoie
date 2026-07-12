defmodule Algoie.Orders.OrderWorkflow do
  @moduledoc """
  Creates orders with stock decrement and coupon application inside a transaction.
  """

  alias Algoie.Repo
  alias Algoie.Products.Variant
  alias Algoie.Customers.Coupon
  alias Algoie.Orders.Order
  alias Algoie.Orders.OrderLineItem
  import Ecto.Query
  require Ash.Query

  @doc """
  Create an order from variant_quantities list.

  Returns {:ok, order} or {:error, reason}.
  """
  def create_order(tenant, attrs, _actor) do
    store_id = attrs.store_id
    customer_id = attrs.customer_id
    variant_quantities = attrs.variant_quantities
    coupon_code = attrs[:coupon_code]

    Repo.transaction(fn ->
      with {:ok, :valid} <- validate_variants_active(variant_quantities, store_id, tenant),
           {:ok, :valid} <- validate_stock(variant_quantities, store_id, tenant),
           {:ok, totals} <- calculate_totals(variant_quantities, store_id, tenant),
           {:ok, coupon} <- maybe_apply_coupon(coupon_code, store_id, tenant),
           {:ok, final_total} <- apply_coupon_to_total(totals, coupon),
           {:ok, :ok} <- decrement_stock(variant_quantities, store_id, tenant),
           {:ok, order} <- create_order_record(store_id, customer_id, coupon, final_total, tenant),
           {:ok, :ok} <- create_line_items(order, variant_quantities, store_id, tenant),
           {:ok, :ok} <- maybe_increment_coupon_usage(coupon, tenant) do
        order
      else
        {:error, reason} -> Repo.rollback(reason)
        {:rollback, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp validate_variants_active(variant_quantities, store_id, tenant) do
    variant_ids = Enum.map(variant_quantities, & &1.variant_id)

    with {:ok, variants} <-
           Variant
           |> Ash.Query.filter(id in ^variant_ids and store_id == ^store_id)
           |> Ash.Query.for_read(:read)
           |> Ash.read(tenant: tenant, authorize?: false),
         true <- length(variants) == length(variant_ids) do
      # Check that all parent products are active
      product_ids = Enum.map(variants, & &1.product_id) |> Enum.uniq()

      case Algoie.Products.Product
           |> Ash.Query.filter(id in ^product_ids and status == :active)
           |> Ash.Query.for_read(:read)
           |> Ash.read(tenant: tenant, authorize?: false) do
        {:ok, active_products} when length(active_products) == length(product_ids) ->
          {:ok, :valid}

        _ ->
          {:error, :inactive_products}
      end
    else
      _ -> {:error, :inactive_products}
    end
  end

  defp validate_stock(variant_quantities, store_id, tenant) do
    result =
      Enum.reduce_while(variant_quantities, {:ok, :valid}, fn %{variant_id: vid, quantity: qty},
                                                              _acc ->
        case Variant
             |> Ash.Query.filter(id == ^vid and store_id == ^store_id)
             |> Ash.Query.for_read(:read)
             |> Ash.read_one(tenant: tenant, authorize?: false) do
          {:ok, %{stock: stock}} when stock < qty ->
            {:halt, {:error, :insufficient_stock}}

          {:ok, _} ->
            {:cont, {:ok, :valid}}

          _ ->
            {:halt, {:error, :variant_not_found}}
        end
      end)

    result
  end

  defp calculate_totals(variant_quantities, store_id, tenant) do
    result =
      Enum.reduce_while(variant_quantities, {:ok, Decimal.new(0)}, fn %{
                                                                        variant_id: vid,
                                                                        quantity: qty
                                                                      },
                                                                      {:ok, acc} ->
        case Variant
             |> Ash.Query.filter(id == ^vid and store_id == ^store_id)
             |> Ash.Query.for_read(:read)
             |> Ash.read_one(tenant: tenant, authorize?: false) do
          {:ok, %{price: price}} ->
            {:cont, {:ok, Decimal.add(acc, Decimal.mult(price, Decimal.new(qty)))}}

          _ ->
            {:halt, {:error, :variant_not_found}}
        end
      end)

    result
  end

  defp maybe_apply_coupon(nil, _store_id, _tenant), do: {:ok, nil}

  defp maybe_apply_coupon(code, store_id, tenant) do
    case Coupon
         |> Ash.Query.filter(code == ^code and store_id == ^store_id)
         |> Ash.Query.for_read(:read)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, coupon} ->
        if Algoie.Customers.coupon_valid_for_use?(coupon) do
          {:ok, coupon}
        else
          {:error, :invalid_coupon}
        end

      _ ->
        {:error, :coupon_not_found}
    end
  end

  defp apply_coupon_to_total(total, nil), do: {:ok, total}

  defp apply_coupon_to_total(total, %{discount_type: :percent, discount_value: pct}) do
    discount = total |> Decimal.mult(pct) |> Decimal.div(Decimal.new("100")) |> Decimal.round(2)
    {:ok, Decimal.sub(total, discount)}
  end

  defp apply_coupon_to_total(total, %{discount_type: :fixed, discount_value: fixed}) do
    {:ok, total |> Decimal.sub(fixed) |> Decimal.round(2)}
  end

  defp decrement_stock(variant_quantities, store_id, tenant) do
    result =
      Enum.reduce_while(variant_quantities, {:ok, :ok}, fn %{variant_id: vid, quantity: qty},
                                                           {:ok, :ok} ->
        prefix = tenant

        case from(v in Variant,
               where: v.id == ^Ecto.UUID.dump!(vid) and v.store_id == ^Ecto.UUID.dump!(store_id),
               lock: "FOR UPDATE"
             )
             |> Repo.one(prefix: prefix) do
          nil ->
            {:halt, {:error, :variant_not_found}}

          variant ->
            new_stock = variant.stock - qty

            if new_stock < 0 do
              {:halt, {:error, :insufficient_stock}}
            else
              variant
              |> Ecto.Changeset.change(%{stock: new_stock})
              |> Repo.update!(prefix: prefix)

              {:cont, {:ok, :ok}}
            end
        end
      end)

    result
  end

  defp create_order_record(store_id, customer_id, coupon, total_amount, tenant) do
    attrs = %{
      store_id: store_id,
      customer_id: customer_id,
      status: :pending,
      total_amount: total_amount,
      coupon_id: if(coupon, do: coupon.id)
    }

    Order
    |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, actor: :system)
    |> Ash.create(authorize?: false)
  end

  defp create_line_items(order, variant_quantities, store_id, tenant) do
    result =
      Enum.reduce_while(variant_quantities, {:ok, :ok}, fn %{variant_id: vid, quantity: qty},
                                                           {:ok, :ok} ->
        case Variant
             |> Ash.Query.filter(id == ^vid and store_id == ^store_id)
             |> Ash.Query.for_read(:read)
             |> Ash.read_one(tenant: tenant, authorize?: false) do
          {:ok, %{price: price}} ->
            attrs = %{
              order_id: order.id,
              variant_id: vid,
              quantity: qty,
              unit_price: price
            }

            case OrderLineItem
                 |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, actor: :system)
                 |> Ash.create(authorize?: false) do
              {:ok, _} -> {:cont, {:ok, :ok}}
              error -> {:halt, error}
            end

          _ ->
            {:halt, {:error, :variant_not_found}}
        end
      end)

    result
  end

  defp maybe_increment_coupon_usage(nil, _tenant), do: {:ok, :ok}

  defp maybe_increment_coupon_usage(coupon, tenant) do
    prefix = tenant

    case from(c in Coupon,
           where: c.id == ^Ecto.UUID.dump!(coupon.id),
           lock: "FOR UPDATE"
         )
         |> Repo.one(prefix: prefix) do
      nil ->
        {:error, :coupon_not_found}

      c ->
        c
        |> Ecto.Changeset.change(%{times_used: c.times_used + 1})
        |> Repo.update!(prefix: prefix)

        {:ok, :ok}
    end
  end
end
