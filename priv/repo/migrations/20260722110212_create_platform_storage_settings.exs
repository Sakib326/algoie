defmodule Algoie.Repo.Migrations.CreatePlatformStorageSettings do
  use Ecto.Migration

  def change do
    create table(:platform_storage_settings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :backend, :string, null: false, default: "local"
      add :endpoint, :string
      add :region, :string
      add :bucket, :string
      add :access_key_id, :string
      add :secret_access_key_ciphertext, :text
      add :public_base_url, :string
      add :path_style, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end
  end
end
