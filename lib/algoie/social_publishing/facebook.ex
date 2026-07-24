defmodule Algoie.SocialPublishing.Facebook do
  @moduledoc "Facebook operations used by Channel Studio."

  alias Algoie.ChannelStudio

  def list_posts(params), do: get("/posts", facebook_params(params))
  def get_post(id), do: get("/posts/#{segment(id)}")
  def update_post(id, payload), do: mutate(:put, "/posts/#{segment(id)}", payload)
  def delete_post(id), do: mutate(:delete, "/posts/#{segment(id)}")
  def retry_post(id), do: mutate(:post, "/posts/#{segment(id)}/retry", %{})

  def unpublish_post(id),
    do: mutate(:post, "/posts/#{segment(id)}/unpublish", %{"platform" => "facebook"})

  def edit_published_post(id, payload), do: mutate(:post, "/posts/#{segment(id)}/edit", payload)

  def create_post(payload),
    do: request(:post, "/posts", payload, [], request_headers())

  def pages(account_id), do: get("/accounts/#{segment(account_id)}/facebook-page")

  def set_default_page(account_id, page_id),
    do: mutate(:put, "/accounts/#{segment(account_id)}/facebook-page", %{selectedPageId: page_id})

  def health(profile_id),
    do: get("/accounts/health", profileId: profile_id, platform: "facebook")

  def account_health(account_id), do: get("/accounts/#{segment(account_id)}/health")

  def analytics(params), do: get("/analytics", facebook_params(params))

  def daily_metrics(params), do: get("/analytics/daily-metrics", facebook_params(params))

  def page_insights(account_id, params),
    do: get("/analytics/facebook/page-insights", Keyword.put(params, :accountId, account_id))

  def conversations(params), do: get("/inbox/conversations", facebook_params(params))

  def search_conversations(params),
    do: get("/inbox/conversations/search", facebook_params(params))

  def conversation(id), do: get("/inbox/conversations/#{segment(id)}")

  def update_conversation(id, payload),
    do: mutate(:put, "/inbox/conversations/#{segment(id)}", payload)

  def messages(id, params),
    do: get("/inbox/conversations/#{segment(id)}/messages", params)

  def send_message(id, payload),
    do: mutate(:post, "/inbox/conversations/#{segment(id)}/messages", payload)

  def mark_read(id), do: mutate(:post, "/inbox/conversations/#{segment(id)}/read", %{})

  def comments(params), do: get("/inbox/comments", facebook_params(params))
  def post_comments(post_id, params), do: get("/inbox/comments/#{segment(post_id)}", params)

  def reply_to_comment(post_id, payload),
    do: mutate(:post, "/inbox/comments/#{segment(post_id)}", payload)

  def delete_comment(post_id, comment_id, params \\ []),
    do:
      request(
        :delete,
        "/inbox/comments/#{segment(post_id)}",
        nil,
        Keyword.put(params, :commentId, comment_id),
        request_headers()
      )

  def hide_comment(post_id, comment_id, account_id),
    do: mutate(:post, comment_action_path(post_id, comment_id, "hide"), %{accountId: account_id})

  def unhide_comment(post_id, comment_id, account_id),
    do:
      request(
        :delete,
        comment_action_path(post_id, comment_id, "hide"),
        nil,
        [accountId: account_id],
        request_headers()
      )

  def like_comment(post_id, comment_id, account_id),
    do: mutate(:post, comment_action_path(post_id, comment_id, "like"), %{accountId: account_id})

  def unlike_comment(post_id, comment_id, account_id),
    do:
      request(
        :delete,
        comment_action_path(post_id, comment_id, "like"),
        nil,
        [accountId: account_id],
        request_headers()
      )

  def private_reply(post_id, comment_id, payload),
    do: mutate(:post, comment_action_path(post_id, comment_id, "private-reply"), payload)

  def reviews(params), do: get("/inbox/reviews", facebook_params(params))

  def reply_to_review(review_id, payload),
    do: mutate(:post, "/inbox/reviews/#{segment(review_id)}/reply", payload)

  def messenger_menu(account_id), do: get("/accounts/#{segment(account_id)}/messenger-menu")

  def set_messenger_menu(account_id, payload),
    do: mutate(:put, "/accounts/#{segment(account_id)}/messenger-menu", payload)

  def delete_messenger_menu(account_id),
    do: mutate(:delete, "/accounts/#{segment(account_id)}/messenger-menu")

  def automations(profile_id), do: get("/comment-automations", profileId: profile_id)
  def automation(id), do: get("/comment-automations/#{segment(id)}")
  def create_automation(payload), do: mutate(:post, "/comment-automations", payload)

  def update_automation(id, payload),
    do: mutate(:patch, "/comment-automations/#{segment(id)}", payload)

  def delete_automation(id), do: mutate(:delete, "/comment-automations/#{segment(id)}")

  def automation_logs(id, params),
    do: get("/comment-automations/#{segment(id)}/logs", params)

  def webhook_settings, do: get("/webhooks/settings")
  def create_webhook(payload), do: mutate(:post, "/webhooks/settings", payload)
  def update_webhook(payload), do: mutate(:put, "/webhooks/settings", payload)
  def webhook_logs(params), do: get("/webhooks/logs", params)
  def test_webhook(id), do: mutate(:post, "/webhooks/test", %{webhookId: id})

  defp get(path, params \\ []), do: request(:get, path, nil, params)

  defp mutate(method, path, body \\ nil),
    do: request(method, path, body, [], request_headers())

  defp request(method, path, body, params, headers \\ []),
    do: ChannelStudio.request(method, path, body, compact_params(params), headers)

  defp request_headers, do: [{"x-request-id", Ecto.UUID.generate()}]

  defp facebook_params(params) do
    params
    |> Keyword.put_new(:platform, "facebook")
    |> compact_params()
  end

  defp compact_params(params), do: Enum.reject(params, fn {_key, value} -> value in [nil, ""] end)

  defp comment_action_path(post_id, comment_id, action) do
    "/inbox/comments/#{segment(post_id)}/#{segment(comment_id)}/#{action}"
  end

  defp segment(value), do: value |> to_string() |> URI.encode_www_form()
end
