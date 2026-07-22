defmodule Algoie.Repo.Migrations.CreateSocialPublishingSettings do
  use Ecto.Migration

  def change do
    create table(:social_publishing_settings, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :active_adapter, :text, null: false, default: "zernio"
      add :api_key_ciphertext, :text
      timestamps(type: :utc_datetime_usec)
    end
  end
end
