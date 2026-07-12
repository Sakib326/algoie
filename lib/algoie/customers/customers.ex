defmodule Algoie.Customers do
  use Ash.Domain

  resources do
    resource(Algoie.Customers.Customer)
    resource(Algoie.Customers.Coupon)
  end

  @doc """
  Check if a coupon is valid for use right now.
  """
  def coupon_valid_for_use?(coupon) do
    now = DateTime.utc_now()

    started? =
      is_nil(coupon.starts_at) or DateTime.compare(coupon.starts_at, now) != :gt

    not_expired? =
      is_nil(coupon.expires_at) or DateTime.compare(coupon.expires_at, now) == :gt

    usage_ok? = is_nil(coupon.usage_limit) or coupon.times_used < coupon.usage_limit
    started? and not_expired? and usage_ok?
  end
end
