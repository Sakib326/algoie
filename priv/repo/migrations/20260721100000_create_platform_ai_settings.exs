defmodule Algoie.Repo.Migrations.CreatePlatformAiSettings do
  use Ecto.Migration

  def change do
    create table(:platform_ai_settings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :enabled, :boolean, null: false, default: false
      add :openrouter_api_key_ciphertext, :text
      add :default_model, :string, null: false, default: ""
      add :fallback_model, :string
      add :monthly_budget_cents, :integer
      add :max_run_cost_cents, :integer, null: false, default: 25
      add :allowed_models, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end
  end
end
