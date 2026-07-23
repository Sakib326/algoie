defmodule Algoie.Repo.TenantMigrations.CreateStoreEmailSettings do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:store_email_settings, primary_key: false, prefix: prefix()) do
      add :id, :uuid, primary_key: true
      add :store_id, references(:stores, type: :uuid, on_delete: :delete_all), null: false
      add :use_platform, :boolean, null: false, default: true
      add :enabled, :boolean, null: false, default: true
      add :smtp_host, :string
      add :smtp_port, :integer, null: false, default: 587
      add :smtp_username, :string
      add :smtp_password_ciphertext, :text
      add :smtp_password_hint, :string
      add :smtp_auth, :string, null: false, default: "if_available"
      add :smtp_tls, :string, null: false, default: "if_available"
      add :from_name, :string
      add :from_address, :string
      add :reply_to, :string

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:store_email_settings, [:store_id], prefix: prefix())
  end
end
