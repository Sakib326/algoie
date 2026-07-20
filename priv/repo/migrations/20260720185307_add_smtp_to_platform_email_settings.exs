defmodule Algoie.Repo.Migrations.AddSmtpToPlatformEmailSettings do
  use Ecto.Migration

  def change do
    alter table(:platform_email_settings) do
      add :smtp_host, :string
      add :smtp_port, :integer, null: false, default: 587
      add :smtp_username, :string
      add :smtp_password_ciphertext, :text
      add :smtp_password_hint, :string
      add :smtp_auth, :string, null: false, default: "if_available"
      add :smtp_tls, :string, null: false, default: "if_available"
    end
  end
end
