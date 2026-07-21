defmodule Algoie.AI.Message do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ai_messages" do
    field :role, Ecto.Enum, values: [:user, :assistant]
    field :content, :string
    belongs_to :conversation, Algoie.AI.Conversation
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
