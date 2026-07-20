defmodule Algoie.PlatformEmailSettingsTest do
  use Algoie.DataCase, async: true

  alias Algoie.PlatformEmailSettings

  test "validates required provider credentials and sender fields" do
    changeset =
      PlatformEmailSettings.changeset(%PlatformEmailSettings{}, %{
        "provider" => "resend",
        "from_name" => "Algoie",
        "from_address" => "not-an-email",
        "app_url" => "example.com"
      })

    refute changeset.valid?
    assert "is required for Resend" in errors_on(changeset).api_key
    assert "has invalid format" in errors_on(changeset).from_address
    assert "must start with http:// or https://" in errors_on(changeset).app_url
  end

  test "encrypts a newly supplied provider key" do
    changeset =
      PlatformEmailSettings.changeset(%PlatformEmailSettings{}, %{
        "provider" => "resend",
        "api_key" => "re_secret_key",
        "from_name" => "Algoie",
        "from_address" => "mail@example.com",
        "app_url" => "https://example.com"
      })

    assert changeset.valid?
    ciphertext = Ecto.Changeset.get_change(changeset, :api_key_ciphertext)
    assert is_binary(ciphertext)
    assert ciphertext != "re_secret_key"
  end

  test "validates and encrypts SMTP credentials" do
    changeset =
      PlatformEmailSettings.changeset(%PlatformEmailSettings{}, %{
        "provider" => "smtp",
        "smtp_host" => "sandbox.smtp.mailtrap.io",
        "smtp_port" => "2525",
        "smtp_username" => "a7aafb37bed08f",
        "smtp_password" => "secret-c188",
        "smtp_auth" => "if_available",
        "smtp_tls" => "if_available",
        "from_name" => "Algoie",
        "from_address" => "mail@example.com",
        "app_url" => "https://example.com"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :smtp_password_hint) == "c188"
    ciphertext = Ecto.Changeset.get_change(changeset, :smtp_password_ciphertext)
    assert is_binary(ciphertext)
    refute ciphertext =~ "secret-c188"
  end
end
