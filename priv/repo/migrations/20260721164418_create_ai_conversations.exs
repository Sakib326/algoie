defmodule Algoie.Repo.Migrations.CreateAiConversations do
  use Ecto.Migration

  def change do
    create table(:ai_conversations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :store_id, :uuid, null: false
      add :tenant, :string, null: false
      add :title, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:ai_conversations, [:user_id, :store_id, :updated_at])

    create table(:ai_messages, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :conversation_id,
          references(:ai_conversations, type: :uuid, on_delete: :delete_all), null: false

      add :role, :string, null: false
      add :content, :text, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_messages, [:conversation_id, :inserted_at])

    create constraint(:ai_messages, :valid_ai_message_role,
             check: "role IN ('user', 'assistant')"
           )
  end
end
