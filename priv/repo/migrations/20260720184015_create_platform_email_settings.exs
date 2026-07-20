defmodule Algoie.Repo.Migrations.CreatePlatformEmailSettings do
  use Ecto.Migration

  def change do
    create table(:platform_email_settings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false, default: "local"
      add :enabled, :boolean, null: false, default: true
      add :api_key_ciphertext, :text
      add :from_name, :string, null: false, default: "Algoie"
      add :from_address, :string, null: false, default: "noreply@localhost"
      add :reply_to, :string
      add :app_url, :string, null: false, default: "http://localhost:4000"

      timestamps(type: :utc_datetime_usec)
    end
  end
end
