defmodule Algoie.StoreEmailSettingsTest do
  use Algoie.DataCase, async: true

  alias Algoie.StoreEmailSettings

  test "platform fallback requires no custom credentials" do
    changeset = StoreEmailSettings.changeset(%StoreEmailSettings{}, %{"use_platform" => "true"})
    assert changeset.valid?
  end

  test "custom SMTP validates and encrypts its password" do
    changeset =
      StoreEmailSettings.changeset(%StoreEmailSettings{}, %{
        "use_platform" => "false",
        "smtp_host" => "sandbox.smtp.mailtrap.io",
        "smtp_port" => "2525",
        "smtp_username" => "store-user",
        "smtp_password" => "store-secret-c188",
        "smtp_auth" => "if_available",
        "smtp_tls" => "if_available",
        "from_name" => "Demo Store",
        "from_address" => "orders@example.com"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :smtp_password_hint) == "c188"
    ciphertext = Ecto.Changeset.get_change(changeset, :smtp_password_ciphertext)
    assert is_binary(ciphertext)
    refute ciphertext =~ "store-secret-c188"
  end

  test "custom SMTP reports missing credentials" do
    changeset = StoreEmailSettings.changeset(%StoreEmailSettings{}, %{"use_platform" => "false"})
    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).smtp_host
    assert "is required for custom SMTP" in errors_on(changeset).smtp_password
  end
end
