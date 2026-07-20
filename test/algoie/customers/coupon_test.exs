defmodule Algoie.Customers.CouponTest do
  use ExUnit.Case, async: true

  alias Algoie.Customers

  test "percentage discount is calculated and rounded" do
    coupon = %{discount_type: :percent, discount_value: Decimal.new("12.5")}
    assert Customers.discount_for(coupon, Decimal.new("99.99")) == Decimal.new("12.50")
  end

  test "fixed discount never reduces an order below zero" do
    coupon = %{discount_type: :fixed, discount_value: Decimal.new("100")}
    assert Customers.discount_for(coupon, Decimal.new("40")) == Decimal.new("40")
  end

  test "minimum order and active flag are enforced" do
    coupon = %{
      starts_at: nil,
      expires_at: nil,
      usage_limit: nil,
      times_used: 0,
      min_order_value: Decimal.new("500"),
      active?: true
    }

    refute Customers.coupon_valid_for_use?(coupon, Decimal.new("499.99"))
    assert Customers.coupon_valid_for_use?(coupon, Decimal.new("500"))
    refute Customers.coupon_valid_for_use?(%{coupon | active?: false}, Decimal.new("500"))
  end

  test "usage and expiry are enforced" do
    now = DateTime.utc_now()

    coupon = %{
      starts_at: DateTime.add(now, -60),
      expires_at: DateTime.add(now, 60),
      usage_limit: 1,
      times_used: 1,
      min_order_value: nil,
      active?: true
    }

    refute Customers.coupon_valid_for_use?(coupon)

    refute Customers.coupon_valid_for_use?(%{
             coupon
             | times_used: 0,
               expires_at: DateTime.add(now, -1)
           })
  end
end
