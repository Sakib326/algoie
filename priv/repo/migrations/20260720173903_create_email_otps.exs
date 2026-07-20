defmodule Algoie.Repo.Migrations.CreateEmailOtps do
  use Ecto.Migration

  def change do
    create table(:email_otps, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :email, :citext, null: false
      add :purpose, :string, null: false
      add :context, :string, null: false, default: "platform"
      add :code_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :attempts, :integer, null: false, default: 0
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:email_otps, [:email, :purpose, :context], prefix: "public")
    create index(:email_otps, [:expires_at], prefix: "public")
  end
end
