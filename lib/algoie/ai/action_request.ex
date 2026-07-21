defmodule Algoie.AI.ActionRequest do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ai_action_requests" do
    field :user_id, :binary_id
    field :store_id, :binary_id
    field :tool_id, :string
    field :arguments, :map
    field :preview, :map
    field :status, Ecto.Enum, values: [:pending, :approved, :rejected, :failed]
    belongs_to :conversation, Algoie.AI.Conversation
    timestamps(type: :utc_datetime)
  end
end
