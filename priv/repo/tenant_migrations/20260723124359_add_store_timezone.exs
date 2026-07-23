defmodule Algoie.Repo.Migrations.AddStoreTimezone do
  use Ecto.Migration

  def change do
    alter table(:stores, prefix: prefix()) do
      add_if_not_exists :timezone, :text, null: false, default: "Asia/Dhaka"
    end
  end
end
