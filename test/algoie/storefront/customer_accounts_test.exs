defmodule Algoie.Storefront.CustomerAccountsTest do
  use ExUnit.Case, async: true

  alias Algoie.Customers.Customer

  test "registration hashes the password instead of storing it directly" do
    changeset =
      Ash.Changeset.for_create(
        Customer,
        :register,
        %{
          name: "Customer",
          email: "customer@example.com",
          store_id: Ecto.UUID.generate(),
          password: "secure-password"
        },
        tenant: "tenant_test"
      )

    hash = Ash.Changeset.get_attribute(changeset, :hashed_password)

    assert changeset.valid?
    assert hash != "secure-password"
    assert Bcrypt.verify_pass("secure-password", hash)
  end

  test "registration rejects short passwords" do
    changeset =
      Ash.Changeset.for_create(
        Customer,
        :register,
        %{
          name: "Customer",
          email: "customer@example.com",
          store_id: Ecto.UUID.generate(),
          password: "short"
        },
        tenant: "tenant_test"
      )

    refute changeset.valid?
    assert Enum.any?(changeset.errors, &(Exception.message(&1) =~ "at least 8 characters"))
  end

  test "password reset action replaces the password hash" do
    customer = %Customer{
      id: Ecto.UUID.generate(),
      name: "Customer",
      store_id: Ecto.UUID.generate(),
      hashed_password: Bcrypt.hash_pwd_salt("old-password")
    }

    changeset = Ash.Changeset.for_update(customer, :reset_password, %{password: "new-password"})
    hash = Ash.Changeset.get_attribute(changeset, :hashed_password)

    assert changeset.valid?
    refute Bcrypt.verify_pass("old-password", hash)
    assert Bcrypt.verify_pass("new-password", hash)
  end
end
