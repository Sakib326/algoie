defmodule Algoie.Repo.Migrations.CreatePlatformAiUsage do
  use Ecto.Migration

  def change do
    create table(:platform_ai_usage, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :model, :string, null: false
      add :tokens_prompt, :integer, null: false, default: 0
      add :tokens_completion, :integer, null: false, default: 0
      add :cost_cents, :integer, null: false, default: 0
      add :store_id, :uuid
      add :user_id, :uuid
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:platform_ai_usage, [:inserted_at])
    create index(:platform_ai_usage, [:model])
  end
end
