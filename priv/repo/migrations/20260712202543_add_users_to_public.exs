defmodule Algoie.Repo.Migrations.AddUsersToPublic do
  use Ecto.Migration

  def up do
    create table(:users, primary_key: false, prefix: "public") do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :text, null: false
      add :name, :text
      add :default_tenant, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:users, [:email], prefix: "public")
  end

  def down do
    drop table("users", prefix: "public")
  end
end
