defmodule Algoie.Customers do
  use Ash.Domain

  resources do
    resource(Algoie.Customers.Customer)
    resource(Algoie.Customers.CustomerAddress)
    resource(Algoie.Customers.Coupon)
  end

  @doc """
  Check if a coupon is valid for use right now.
  """
  def coupon_valid_for_use?(coupon, subtotal \\ nil) do
    now = DateTime.utc_now()

    started? =
      is_nil(coupon.starts_at) or DateTime.compare(coupon.starts_at, now) != :gt

    not_expired? =
      is_nil(coupon.expires_at) or DateTime.compare(coupon.expires_at, now) == :gt

    usage_ok? = is_nil(coupon.usage_limit) or coupon.times_used < coupon.usage_limit
    active? = Map.get(coupon, :active?, true)

    minimum_ok? =
      is_nil(subtotal) or is_nil(coupon.min_order_value) or
        Decimal.compare(subtotal, coupon.min_order_value) != :lt

    active? and started? and not_expired? and usage_ok? and minimum_ok?
  end

  def discount_for(coupon, subtotal) do
    discount =
      case coupon.discount_type do
        :percent -> Decimal.div(Decimal.mult(subtotal, coupon.discount_value), Decimal.new(100))
        :fixed -> coupon.discount_value
      end

    Decimal.min(Decimal.round(discount, 2), subtotal)
  end
end
