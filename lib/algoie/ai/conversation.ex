defmodule Algoie.AI.Conversation do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ai_conversations" do
    field :store_id, :binary_id
    field :tenant, :string
    field :title, :string
    belongs_to :user, Algoie.Accounts.User
    has_many :messages, Algoie.AI.Message
    timestamps(type: :utc_datetime)
  end
end
