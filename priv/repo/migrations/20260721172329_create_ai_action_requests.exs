defmodule Algoie.Repo.Migrations.CreateAiActionRequests do
  use Ecto.Migration

  def change do
    create table(:ai_action_requests, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :conversation_id,
          references(:ai_conversations, type: :uuid, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :store_id, :uuid, null: false
      add :tool_id, :string, null: false
      add :arguments, :map, null: false
      add :preview, :map, null: false
      add :status, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime)
    end

    create index(:ai_action_requests, [:conversation_id, :status, :inserted_at])
    create index(:ai_action_requests, [:user_id, :store_id, :status])

    create constraint(:ai_action_requests, :valid_ai_action_status,
             check: "status IN ('pending', 'approved', 'rejected', 'failed')"
           )
  end
end
