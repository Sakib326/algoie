defmodule Algoie.Accounts.UserPasswordTest do
  use ExUnit.Case, async: true

  alias Algoie.Accounts.User

  test "password reset action replaces the password hash" do
    user = %User{
      id: Ecto.UUID.generate(),
      email: Ash.CiString.new("owner@example.com"),
      hashed_password: Bcrypt.hash_pwd_salt("old-password")
    }

    changeset = Ash.Changeset.for_update(user, :reset_password, %{password: "new-password"})
    hash = Ash.Changeset.get_attribute(changeset, :hashed_password)

    assert changeset.valid?
    refute Bcrypt.verify_pass("old-password", hash)
    assert Bcrypt.verify_pass("new-password", hash)
  end
end
