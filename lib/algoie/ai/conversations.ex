defmodule Algoie.AI.Conversations do
  @moduledoc "Store-scoped, user-owned assistant conversation history."

  import Ecto.Query
  alias Algoie.AI.{ActionRequest, Conversation, Message}
  alias Algoie.Repo

  @message_page_size 30

  def list(user_id, store_id) do
    from(c in Conversation,
      where: c.user_id == ^user_id and c.store_id == ^store_id,
      order_by: [desc: c.updated_at],
      limit: 40
    )
    |> Repo.all()
  end

  def get(id, user_id, store_id) do
    from(c in Conversation,
      where: c.id == ^id and c.user_id == ^user_id and c.store_id == ^store_id
    )
    |> Repo.one()
  end

  def message_page(conversation_id, cursor \\ nil) do
    query =
      from(m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^(@message_page_size + 1)
      )

    query =
      case cursor do
        {inserted_at, id} ->
          from(m in query,
            where: m.inserted_at < ^inserted_at or (m.inserted_at == ^inserted_at and m.id < ^id)
          )

        nil ->
          query
      end

    fetched = Repo.all(query)
    has_more? = length(fetched) > @message_page_size
    messages = fetched |> Enum.take(@message_page_size) |> Enum.reverse()

    %{
      messages: messages,
      has_more?: has_more?,
      cursor: oldest_message_cursor(messages)
    }
  end

  def start(user_id, store_id, tenant, instruction) do
    %Conversation{
      user_id: user_id,
      store_id: store_id,
      tenant: tenant,
      title: title(instruction)
    }
    |> Repo.insert()
  end

  def add_message(conversation_id, role, content) when role in [:user, :assistant] do
    Repo.transaction(fn ->
      message =
        %Message{conversation_id: conversation_id, role: role, content: content}
        |> Repo.insert!()

      from(c in Conversation, where: c.id == ^conversation_id)
      |> Repo.update_all(set: [updated_at: DateTime.utc_now(:second)])

      message
    end)
  end

  def delete(id, user_id, store_id) do
    from(c in Conversation,
      where: c.id == ^id and c.user_id == ^user_id and c.store_id == ^store_id
    )
    |> Repo.delete_all()
  end

  def replace_pending_actions(conversation_id, user_id, store_id, approvals) do
    Repo.transaction(fn ->
      from(a in ActionRequest,
        where:
          a.conversation_id == ^conversation_id and a.user_id == ^user_id and
            a.store_id == ^store_id and a.status == :pending
      )
      |> Repo.update_all(set: [status: :rejected, updated_at: DateTime.utc_now(:second)])

      Enum.map(approvals, fn approval ->
        %ActionRequest{
          conversation_id: conversation_id,
          user_id: user_id,
          store_id: store_id,
          tool_id: approval.tool_id,
          arguments: approval.arguments,
          preview: stringify_map(approval.preview),
          status: :pending
        }
        |> Repo.insert!()
      end)
    end)
  end

  def pending_actions(conversation_id, user_id, store_id) do
    from(a in ActionRequest,
      where:
        a.conversation_id == ^conversation_id and a.user_id == ^user_id and
          a.store_id == ^store_id and a.status == :pending,
      order_by: [asc: a.inserted_at]
    )
    |> Repo.all()
  end

  def resolve_action(id, user_id, store_id, status)
      when status in [:approved, :rejected, :failed] do
    from(a in ActionRequest,
      where:
        a.id == ^id and a.user_id == ^user_id and a.store_id == ^store_id and
          a.status == :pending
    )
    |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now(:second)])
  end

  defp title(instruction) do
    instruction
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 64)
  end

  defp oldest_message_cursor([oldest | _]), do: {oldest.inserted_at, oldest.id}
  defp oldest_message_cursor([]), do: nil

  defp stringify_map(map), do: Jason.decode!(Jason.encode!(map))
end
