defmodule Algoie.ChannelStudio.Inbox do
  @moduledoc "Provider-neutral messaging and organic-comment operations."

  alias Algoie.ChannelStudio

  def conversations(params), do: ChannelStudio.get("/inbox/conversations", params)
  def conversation(id), do: ChannelStudio.get("/inbox/conversations/#{ChannelStudio.segment(id)}")

  def messages(id, params \\ []) do
    ChannelStudio.get("/inbox/conversations/#{ChannelStudio.segment(id)}/messages", params)
  end

  def send_message(id, payload) do
    ChannelStudio.mutate(
      :post,
      "/inbox/conversations/#{ChannelStudio.segment(id)}/messages",
      payload
    )
  end

  def mark_read(id, account_id) do
    ChannelStudio.mutate(:post, "/inbox/conversations/#{ChannelStudio.segment(id)}/read", %{
      "accountId" => account_id
    })
  end

  def commented_posts(params), do: ChannelStudio.get("/inbox/comments", params)

  def comments(post_id, params \\ []) do
    ChannelStudio.get("/inbox/comments/#{ChannelStudio.segment(post_id)}", params)
  end

  def reply(post_id, payload) do
    ChannelStudio.mutate(:post, "/inbox/comments/#{ChannelStudio.segment(post_id)}", payload)
  end

  def ad_comments(ad_id, params \\ []) do
    ChannelStudio.get("/ads/#{ChannelStudio.segment(ad_id)}/comments", params)
  end
end
