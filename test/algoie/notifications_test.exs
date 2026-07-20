defmodule Algoie.NotificationsTest do
  use ExUnit.Case, async: false

  setup context do
    Swoosh.TestAssertions.set_swoosh_global(context)
  end

  test "sends the owner welcome email" do
    assert :ok = Algoie.Notifications.welcome_owner("owner@example.com", "Acme Store")

    assert_receive {:email, email}, 1_000
    assert email.subject == "Welcome to Algoie"
    assert email.to == [{"", "owner@example.com"}]
    assert email.text_body =~ "Acme Store has been created"
  end

  test "sends an order confirmation when the customer supplied an email" do
    order = %{
      customer_email: "customer@example.com",
      order_number: "ORD-1001",
      total_amount: Decimal.new("125.50")
    }

    assert :ok = Algoie.Notifications.order_confirmation(order, "Acme Store")

    assert_receive {:email, email}, 1_000
    assert email.subject == "Order ORD-1001 confirmed"
    assert email.text_body =~ "BDT 125.5"
  end

  test "skips customer email when no address was supplied" do
    assert :skipped =
             Algoie.Notifications.order_confirmation(%{customer_email: nil}, "Acme Store")

    refute_receive {:email, _email}, 100
  end

  test "sends order status updates" do
    order = %{
      customer_email: "customer@example.com",
      order_number: "ORD-1001",
      status: :fulfilled
    }

    assert :ok = Algoie.Notifications.order_status_changed(order, "Acme Store")
    assert_receive {:email, email}, 1_000
    assert email.subject == "Order ORD-1001: Fulfilled"
  end
end
