defmodule AlgoieWeb.FacebookLive do
  use AlgoieWeb, :live_view
  import AlgoieWeb.FacebookComponents

  alias Algoie.SocialPublishing.Facebook
  alias AlgoieWeb.FacebookStudio

  @post_defaults %{
    "content" => "",
    "content_type" => "feed",
    "media_type" => "image",
    "media_urls" => "",
    "library_urls" => [],
    "title" => "",
    "first_comment" => "",
    "countries" => "",
    "delivery" => "now",
    "scheduled_for" => "",
    "selected_pages" => [],
    "carousel" => false,
    "carousel_link" => "",
    "carousel_cards" => "",
    "geo_enabled" => false
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> FacebookStudio.load()
      |> FacebookStudio.subscribe()
      |> assign(:page_title, "Facebook Studio")
      |> assign(:manage_social, FacebookStudio.manage?(socket))
      |> assign(:loading, false)
      |> assign(:locked, false)
      |> assign(:provider_error, nil)
      |> assign(:inbox_tab, "messages")
      |> assign(:analytics_tab, "posts")
      |> assign(:session_page_id, nil)
      |> assign(:connection_data, nil)
      |> assign(:sidebar_collapsed, false)
      |> assign(:data, %{})
      |> assign(:post_form, to_form(@post_defaults, as: :facebook_post))
      |> assign(
        :message_form,
        to_form(%{"message" => "", "attachment_url" => "", "tag" => ""}, as: :message)
      )
      |> assign(:reply_form, to_form(%{"message" => ""}, as: :reply))
      |> assign(:automation_form, automation_form())
      |> assign(:menu_form, to_form(%{"json" => "{\n  \"persistent_menu\": []\n}"}, as: :menu))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if socket.assigns.live_action == :inbox do
        assign(socket, :inbox_tab, inbox_section(params["tab"]))
      else
        socket
      end

    send(self(), {:load_facebook_action, socket.assigns.live_action, params})
    {:noreply, socket |> assign(:loading, true) |> assign(:provider_error, nil)}
  end

  @impl true
  def handle_event("validate-post", %{"facebook_post" => params}, socket) do
    params = normalize_post_params(params)

    {:noreply,
     assign(socket, :post_form, to_form(Map.merge(@post_defaults, params), as: :facebook_post))}
  end

  def handle_event("toggle-facebook-sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_collapsed, &(!&1))}
  end

  def handle_event("select-studio-page", %{"page_id" => page_id}, socket) do
    params =
      socket.assigns.post_form.params
      |> Map.new()
      |> Map.put("selected_pages", [page_id])

    {:noreply,
     socket
     |> assign(:session_page_id, page_id)
     |> assign(:post_form, to_form(Map.merge(@post_defaults, params), as: :facebook_post))}
  end

  def handle_event("select-inbox-tab", %{"tab" => tab}, socket)
      when tab in ["messages", "comments", "reviews"] do
    socket = assign(socket, :inbox_tab, tab)

    if tab_data_loaded?(socket.assigns.data, tab) do
      {:noreply, socket}
    else
      send(self(), {:load_inbox_tab, tab})
      {:noreply, assign(socket, :loading, true)}
    end
  end

  def handle_event("select-comment-post", %{"id" => id}, socket) do
    post = Enum.find(socket.assigns.data[:comment_posts] || [], &(comment_post_id(&1) == id))

    if post do
      send(self(), {:load_comment_thread, post})

      {:noreply,
       socket
       |> assign(:loading, true)
       |> assign(
         :data,
         Map.merge(socket.assigns.data, %{selected_comment_post: post, comments: []})
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select-analytics-tab", %{"tab" => tab}, socket)
      when tab in ["posts", "page"] do
    {:noreply, assign(socket, :analytics_tab, tab)}
  end

  def handle_event("publish", %{"facebook_post" => params}, socket) do
    params = normalize_post_params(params)

    with :ok <- authorize(socket),
         {:ok, payload} <- build_post_payload(params, socket),
         {:ok, _} <- Facebook.create_post(payload) do
      {:noreply,
       socket
       |> assign(:provider_error, nil)
       |> assign(:post_form, to_form(@post_defaults, as: :facebook_post))
       |> put_flash(:info, delivery_success(params["delivery"]))}
    else
      {:error, reason} -> {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("post-action", %{"action" => action, "id" => id}, socket) do
    result =
      case action do
        "retry" -> Facebook.retry_post(id)
        "unpublish" -> Facebook.unpublish_post(id)
        "delete" -> Facebook.delete_post(id)
        _ -> {:error, :unsupported}
      end

    filters = socket.assigns.data[:filters] || %{}
    {:noreply, mutation_result(socket, result, "Post updated", &load_posts(&1, filters))}
  end

  def handle_event("filter-posts", %{"filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/facebook/posts?#{params}")}
  end

  def handle_event("select-conversation", %{"id" => id}, socket) do
    send(self(), {:load_conversation, id})

    {:noreply,
     socket
     |> assign(:loading, true)
     |> assign(:data, Map.merge(socket.assigns.data, %{selected_conversation: id, messages: []}))}
  end

  def handle_event("send-message", %{"message" => params}, socket) do
    id = socket.assigns.data[:selected_conversation]

    payload =
      %{
        "message" => String.trim(params["message"] || ""),
        "accountId" => account_id(socket),
        "profileId" => provider_profile_id(socket),
        "platform" => "facebook"
      }
      |> put_trimmed("attachmentUrl", params["attachment_url"])
      |> put_trimmed("tag", params["tag"])

    result = if id, do: Facebook.send_message(id, payload), else: {:error, :conversation_required}

    {:noreply,
     mutation_result(socket, result, "Message sent", fn updated ->
       updated
       |> assign(
         :message_form,
         to_form(%{"message" => "", "attachment_url" => "", "tag" => ""}, as: :message)
       )
       |> load_conversation(id)
     end)}
  end

  def handle_event("conversation-action", %{"action" => action, "id" => id}, socket) do
    result =
      case action do
        "read" -> Facebook.mark_read(id)
        "archive" -> Facebook.update_conversation(id, %{"archived" => true})
        "unarchive" -> Facebook.update_conversation(id, %{"archived" => false})
      end

    {:noreply, mutation_result(socket, result, "Conversation updated", &load_inbox(&1, %{}))}
  end

  def handle_event("engagement-action", params, socket) do
    result = engagement_mutation(params, socket)

    reload = fn updated ->
      if updated.assigns.live_action == :inbox && updated.assigns.inbox_tab == "comments" &&
           updated.assigns.data[:selected_comment_post] do
        load_comment_thread(updated, updated.assigns.data.selected_comment_post)
      else
        load_engagement(updated, %{})
      end
    end

    {:noreply, mutation_result(socket, result, "Facebook engagement updated", reload)}
  end

  def handle_event(
        "reply",
        %{"reply" => %{"message" => message}, "kind" => kind, "entity_id" => id} = params,
        socket
      ) do
    result =
      case kind do
        "comment" ->
          Facebook.reply_to_comment(params["post_id"], %{
            "accountId" => params["account_id"] || account_id(socket),
            "commentId" => id,
            "message" => message
          })

        "review" ->
          Facebook.reply_to_review(id, %{"message" => message})

        "private" ->
          Facebook.private_reply(params["post_id"], id, %{"message" => message})
      end

    {:noreply,
     mutation_result(socket, result, "Reply sent", fn updated ->
       updated = assign(updated, :reply_form, to_form(%{"message" => ""}, as: :reply))

       if updated.assigns.live_action == :inbox && updated.assigns.inbox_tab == "comments" &&
            updated.assigns.data[:selected_comment_post] do
         load_comment_thread(updated, updated.assigns.data[:selected_comment_post])
       else
         load_engagement(updated, %{})
       end
     end)}
  end

  def handle_event("save-automation", %{"automation" => params}, socket) do
    payload = %{
      "profileId" => provider_profile_id(socket),
      "platform" => "facebook",
      "name" => params["name"],
      "keywords" => split_csv(params["keywords"]),
      "replyMessage" => params["reply_message"],
      "dmMessage" => params["dm_message"],
      "enabled" => truthy?(params["enabled"])
    }

    result = Facebook.create_automation(payload)
    {:noreply, mutation_result(socket, result, "Automation created", &load_automations/1)}
  end

  def handle_event("automation-action", %{"action" => action, "id" => id}, socket) do
    result =
      case action do
        "delete" -> Facebook.delete_automation(id)
        "enable" -> Facebook.update_automation(id, %{"enabled" => true})
        "disable" -> Facebook.update_automation(id, %{"enabled" => false})
      end

    {:noreply, mutation_result(socket, result, "Automation updated", &load_automations/1)}
  end

  def handle_event("set-default-page", %{"page_id" => page_id}, socket) do
    result = Facebook.set_default_page(account_id(socket), page_id)
    {:noreply, mutation_result(socket, result, "Default Facebook Page updated", &load_settings/1)}
  end

  def handle_event("save-menu", %{"menu" => %{"json" => json}}, socket) do
    result =
      with {:ok, payload} <- Jason.decode(json),
           {:ok, response} <- Facebook.set_messenger_menu(account_id(socket), payload) do
        {:ok, response}
      end

    {:noreply, mutation_result(socket, result, "Messenger menu saved", &load_settings/1)}
  end

  def handle_event("delete-menu", _params, socket) do
    {:noreply,
     mutation_result(
       socket,
       Facebook.delete_messenger_menu(account_id(socket)),
       "Messenger menu removed",
       &load_settings/1
     )}
  end

  def handle_event("test-webhook", %{"id" => id}, socket) do
    {:noreply,
     mutation_result(socket, Facebook.test_webhook(id), "Test webhook sent", &load_settings/1)}
  end

  @impl true
  def handle_info({:load_facebook_action, action, params}, socket) do
    if socket.assigns.live_action == action do
      {:noreply, socket |> load_action(params) |> assign(:loading, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:load_inbox_tab, tab}, socket) do
    socket =
      case tab do
        "comments" -> load_inbox_comments(socket)
        "reviews" -> load_inbox_reviews(socket)
        _ -> socket
      end

    {:noreply, assign(socket, :loading, false)}
  end

  def handle_info({:load_conversation, id}, socket) do
    if socket.assigns.data[:selected_conversation] == id do
      {:noreply, socket |> load_conversation(id) |> assign(:loading, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:load_comment_thread, post}, socket) do
    if comment_post_id(socket.assigns.data[:selected_comment_post] || %{}) ==
         comment_post_id(post) do
      {:noreply, socket |> load_comment_thread(post) |> assign(:loading, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:zernio_event, _event}, socket) do
    send(self(), {:load_facebook_action, socket.assigns.live_action, %{}})
    {:noreply, assign(socket, :loading, true)}
  end

  def handle_info({:media_manager_updated, "facebook-media", urls}, socket) do
    params = Map.put(socket.assigns.post_form.params || @post_defaults, "library_urls", urls)

    {:noreply,
     assign(socket, :post_form, to_form(Map.merge(@post_defaults, params), as: :facebook_post))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def metric(nil, _key), do: "—"

  def metric(data, key) when is_map(data) do
    value =
      Map.get(data, key) || get_in(data, ["totals", key]) || get_in(data, ["summary", key]) || 0

    if is_number(value), do: to_string(value), else: to_string(value)
  end

  def analytics_overview(data), do: get_in(data, [:analytics, "overview"]) || %{}
  def analytics_posts(data), do: get_in(data, [:analytics, "posts"]) || []
  def daily_metrics(data), do: get_in(data, [:daily, "dailyData"]) || []
  def platform_breakdown(data), do: get_in(data, [:daily, "platformBreakdown"]) || []

  def analytics_total(data, key) do
    overview = analytics_overview(data)
    metric(overview, key)
  end

  def insight_total(nil, _key), do: "—"

  def insight_total(insights, key) do
    insights
    |> get_in(["metrics", key, "total"])
    |> case do
      nil -> "—"
      value -> to_string(value)
    end
  end

  def max_daily(data, key) do
    data
    |> daily_metrics()
    |> Enum.map(&(get_in(&1, ["metrics", key]) || 0))
    |> Enum.max(fn -> 1 end)
    |> max(1)
  end

  def bar_height(day, key, max_value) do
    value = get_in(day, ["metrics", key]) || 0
    max(2, round(value / max_value * 100))
  end

  def post_mode(form), do: form[:content_type].value || "feed"

  def text_length(form), do: form[:content].value |> to_string() |> String.length()

  def selected_media(form) do
    parse_lines(form[:media_urls].value) ++ List.wrap(form[:library_urls].value)
  end

  def active_page(data, session_page_id, account) do
    pages = data[:pages] || []

    default_id =
      session_page_id || data[:selected_page_id] || get_in(account.metadata || %{}, ["pageId"]) ||
        get_in(account.metadata || %{}, ["defaultPageId"])

    Enum.find(pages, &(page_id(&1) == default_id)) || List.first(pages)
  end

  def page_id(page), do: page["id"] || page["pageId"]
  def page_name(page), do: page["name"] || page["pageName"] || "Facebook Page"

  def post_id(post), do: post["_id"] || post["id"]

  def post_thumbnail(post) do
    List.first(post["mediaItems"] || [])
    |> case do
      nil -> post["thumbnailUrl"]
      media -> media["thumbnail"] || media["url"]
    end
  end

  def facebook_platform(post) do
    Enum.find(post["platforms"] || post["platformAnalytics"] || [], fn platform ->
      platform["platform"] == "facebook"
    end) || %{}
  end

  def post_public_url(post) do
    post["platformPostUrl"] || facebook_platform(post)["platformPostUrl"]
  end

  def post_error(post) do
    post["errorMessage"] || facebook_platform(post)["errorMessage"] ||
      get_in(post, ["metadata", "error"])
  end

  def post_day(post) do
    (post["scheduledFor"] || post["publishedAt"] || post["createdAt"] || "Unscheduled")
    |> to_string()
    |> String.slice(0, 10)
  end

  def posts_by_day(posts) do
    posts
    |> Enum.group_by(&post_day/1)
    |> Enum.sort_by(fn {day, _posts} -> day end, :desc)
  end

  def comment_author(comment) do
    comment["authorName"] || comment["userName"] || comment["username"] ||
      get_in(comment, ["from", "name"]) || get_in(comment, ["author", "name"]) ||
      if(is_binary(comment["from"]), do: comment["from"], else: nil) || "Facebook user"
  end

  def comment_post_id(post), do: post["id"] || post["postId"]
  def comment_post_title(post), do: post["content"] || post["message"] || "Media post"

  def account_expired?(%{status: status}), do: status in [:disconnected, :needs_reauth]
  def account_expired?(_), do: false

  def analytics_limited?(data) do
    health = data[:connection_health] || %{}
    health["analyticsAvailable"] == false or health["analytics"] == false
  end

  defp load_action(socket, params) do
    socket = socket |> assign(:locked, false) |> assign(:provider_error, nil)

    socket =
      case socket.assigns.live_action do
        :index ->
          load_overview(socket)

        :publishing ->
          load_publishing(socket)

        :posts ->
          load_posts(socket, params)

        :analytics ->
          load_analytics(socket, params)

        :inbox ->
          case socket.assigns.inbox_tab do
            "comments" -> load_inbox_comments(socket)
            "reviews" -> load_inbox_reviews(socket)
            _ -> load_inbox(socket, params)
          end

        :engagement ->
          load_engagement(socket, params)

        :automations ->
          load_automations(socket)

        :settings ->
          load_settings(socket)
      end

    load_connection_context(socket)
  end

  defp load_connection_context(socket) do
    cond do
      not connected_account?(socket) ->
        socket

      socket.assigns.connection_data ->
        assign(socket, :data, Map.merge(socket.assigns.data, socket.assigns.connection_data))

      true ->
        [
          pages: fn -> Facebook.pages(account_id(socket)) end,
          health: fn -> Facebook.account_health(account_id(socket)) end
        ]
        |> Task.async_stream(fn {key, request} -> {key, request.()} end,
          ordered: false,
          timeout: :infinity
        )
        |> Map.new(fn {:ok, result} -> result end)
        |> then(fn results ->
          {pages, _} = api_value(results[:pages])
          {health, _} = api_value(results[:health])

          connection_data = %{
            pages: items(pages, "pages"),
            selected_page_id: pages && pages["selectedPageId"],
            connection_health: health
          }

          socket
          |> assign(:connection_data, connection_data)
          |> assign(:data, Map.merge(socket.assigns.data, connection_data))
        end)
    end
  end

  defp load_overview(socket) do
    if connected_account?(socket) do
      {health, health_error} = api_value(Facebook.account_health(account_id(socket)))
      {posts, _} = api_value(Facebook.list_posts(account_params(socket) ++ [limit: 5]))

      assign(socket, :data, %{
        health: health,
        posts: items(posts, "posts"),
        health_error: health_error
      })
    else
      assign(socket, :data, %{})
    end
  end

  defp load_publishing(socket) do
    if connected_account?(socket) do
      {pages, error} = api_value(Facebook.pages(account_id(socket)))
      assign(socket, :data, %{pages: items(pages, "pages"), error: error})
    else
      assign(socket, :data, %{})
    end
  end

  defp load_posts(socket, params) do
    if connected_account?(socket) do
      query =
        account_params(socket) ++
          [
            page: params["page"] || 1,
            limit: 20,
            source: params["source"] || "zernio",
            status: params["status"],
            search: params["search"],
            sortBy: params["sort_by"] || "date"
          ]

      {response, error} = api_value(Facebook.list_posts(query))

      assign(socket, :data, %{
        posts: items(response, "posts"),
        pagination: pagination_data(response, params["page"]),
        filters: Map.merge(%{"source" => "zernio", "view" => "list"}, params),
        error: error
      })
    else
      assign(socket, :data, %{})
    end
  end

  defp load_analytics(socket, params) do
    if connected_account?(socket) do
      range = if(params["range"] in ["7", "30", "90", "365"], do: params["range"], else: "30")
      days = String.to_integer(range)
      today = Date.utc_today()
      from = Date.to_iso8601(Date.add(today, -(days - 1)))
      to = Date.to_iso8601(today)
      insights_from = Date.to_iso8601(Date.add(today, -(min(days, 89) - 1)))

      requests = [
        analytics: fn ->
          Facebook.analytics(account_params(socket) ++ [fromDate: from, toDate: to])
        end,
        daily: fn ->
          Facebook.daily_metrics(account_params(socket) ++ [fromDate: from, toDate: to])
        end,
        insights: fn ->
          Facebook.page_insights(account_id(socket),
            since: insights_from,
            until: to,
            metricType: "total_value",
            metrics:
              "page_media_view,page_views_total,page_post_engagements,page_video_views,page_video_view_time,page_follows,followers_gained,followers_lost"
          )
        end
      ]

      results =
        requests
        |> Task.async_stream(fn {key, request} -> {key, request.()} end,
          ordered: false,
          timeout: :infinity
        )
        |> Map.new(fn {:ok, result} -> result end)

      case Enum.find_value(results, fn {_key, result} -> match?({:error, _}, result) && result end) do
        {:error, reason} ->
          assign_api_error(socket, reason, %{range: range, from: from, to: to})

        nil ->
          {:ok, analytics} = results.analytics
          {:ok, daily} = results.daily
          {:ok, insights} = results.insights

          assign(socket, :data, %{
            analytics: analytics,
            daily: daily,
            insights: insights,
            range: range,
            from: from,
            to: to
          })
      end
    else
      assign(socket, :data, %{})
    end
  end

  defp load_inbox(socket, _params) do
    if connected_account?(socket) do
      {response, error} = api_value(Facebook.conversations(account_params(socket) ++ [limit: 40]))

      assign(socket, :data, %{
        conversations: items(response, "conversations"),
        messages: [],
        error: error
      })
    else
      assign(socket, :data, %{})
    end
  end

  defp load_inbox_comments(socket) do
    {posts, error} =
      api_value(Facebook.comments(account_params(socket) ++ [minComments: 1, limit: 50]))

    commented_posts =
      posts
      |> items("data")
      |> Enum.filter(fn post -> (post["commentCount"] || 0) > 0 end)

    assign(
      socket,
      :data,
      Map.merge(socket.assigns.data, %{
        comment_posts: commented_posts,
        selected_comment_post: nil,
        comments: [],
        error: error
      })
    )
  end

  defp load_comment_thread(socket, post) do
    params = [accountId: post["accountId"] || account_id(socket), limit: 100]
    {response, error} = api_value(Facebook.post_comments(comment_post_id(post), params))

    assign(
      socket,
      :data,
      Map.merge(socket.assigns.data, %{
        selected_comment_post: post,
        comments: items(response, "comments"),
        comment_pagination: response && response["pagination"],
        error: error
      })
    )
  end

  defp load_inbox_reviews(socket) do
    {reviews, error} = api_value(Facebook.reviews(account_params(socket) ++ [limit: 50]))

    assign(
      socket,
      :data,
      Map.merge(socket.assigns.data, %{reviews: items(reviews, "reviews"), error: error})
    )
  end

  defp tab_data_loaded?(_data, "messages"), do: true
  defp tab_data_loaded?(data, "comments"), do: Map.has_key?(data, :comment_posts)
  defp tab_data_loaded?(data, "reviews"), do: Map.has_key?(data, :reviews)

  defp inbox_section("comments"), do: "comments"
  defp inbox_section(_), do: "messages"

  defp load_conversation(socket, nil), do: socket

  defp load_conversation(socket, id) do
    {response, error} =
      api_value(
        Facebook.messages(id,
          accountId: account_id(socket),
          limit: 100,
          sortOrder: "asc"
        )
      )

    data =
      Map.merge(socket.assigns.data, %{
        selected_conversation: id,
        messages: items(response, "messages"),
        conversation_error: error
      })

    assign(socket, :data, data)
  end

  defp load_engagement(socket, _params) do
    if connected_account?(socket) do
      {comments, c_error} = api_value(Facebook.comments(account_params(socket) ++ [limit: 50]))
      {reviews, r_error} = api_value(Facebook.reviews(account_params(socket) ++ [limit: 50]))

      assign(socket, :data, %{
        comments: items(comments, "comments"),
        reviews: items(reviews, "reviews"),
        error: c_error || r_error
      })
    else
      assign(socket, :data, %{})
    end
  end

  defp load_automations(socket) do
    if connected_account?(socket) do
      {response, error} = api_value(Facebook.automations(provider_profile_id(socket)))
      assign(socket, :data, %{automations: items(response, "automations"), error: error})
    else
      assign(socket, :data, %{})
    end
  end

  defp load_settings(socket) do
    if connected_account?(socket) do
      {pages, p_error} = api_value(Facebook.pages(account_id(socket)))
      {health, h_error} = api_value(Facebook.account_health(account_id(socket)))
      {menu, m_error} = api_value(Facebook.messenger_menu(account_id(socket)))
      {webhooks, w_error} = api_value(Facebook.webhook_settings())

      socket
      |> assign(:data, %{
        pages: items(pages, "pages"),
        health: health,
        menu: menu,
        webhooks: webhooks,
        error: p_error || h_error || m_error || w_error
      })
      |> assign(
        :menu_form,
        to_form(%{"json" => Jason.encode!(menu || %{}, pretty: true)}, as: :menu)
      )
    else
      assign(socket, :data, %{})
    end
  end

  defp build_post_payload(params, socket) do
    content = String.trim(params["content"] || "")
    urls = (parse_lines(params["media_urls"]) ++ List.wrap(params["library_urls"])) |> Enum.uniq()
    content_type = params["content_type"] || "feed"
    api_content_type = if(content_type == "draft", do: "feed", else: content_type)
    media_type = params["media_type"] || "image"

    params =
      if(content_type == "draft", do: Map.put(params, "delivery", "zernio_draft"), else: params)

    with :ok <- validate_post(content, urls, api_content_type, media_type, params),
         {:ok, delivery} <- delivery_payload(params, socket.assigns.store.timezone) do
      specific =
        %{}
        |> maybe_put("contentType", api_content_type, api_content_type != "feed")
        |> put_trimmed("title", if(api_content_type == "reel", do: params["title"], else: nil))
        |> put_trimmed(
          "firstComment",
          if(content_type != "draft" and api_content_type != "story",
            do: params["first_comment"],
            else: nil
          )
        )
        |> put_countries(
          if(api_content_type != "story" and truthy?(params["geo_enabled"]),
            do: params["countries"],
            else: nil
          )
        )
        |> put_carousel(params, urls, api_content_type, media_type)

      page_ids = List.wrap(params["selected_pages"]) |> Enum.reject(&(&1 == ""))
      page_ids = if page_ids == [], do: [nil], else: page_ids

      platforms =
        Enum.map(page_ids, fn page_id ->
          page_specific = maybe_put(specific, "pageId", page_id, is_binary(page_id))

          %{
            "platform" => "facebook",
            "accountId" => account_id(socket),
            "platformSpecificData" => page_specific
          }
        end)

      payload = %{
        "content" => if(api_content_type == "story", do: "", else: content),
        "mediaItems" =>
          Enum.map(urls, &%{"type" => media_type, "url" => absolute_media_url(&1, socket)}),
        "platforms" => platforms
      }

      {:ok, Map.merge(payload, delivery)}
    end
  end

  defp delivery_payload(%{"delivery" => "schedule", "scheduled_for" => value}, timezone) do
    with {:ok, naive} <-
           NaiveDateTime.from_iso8601(
             value <> if(String.length(value) == 16, do: ":00", else: "")
           ),
         {:ok, datetime} <- local_to_utc(naive, timezone) do
      if DateTime.compare(datetime, DateTime.utc_now()) == :gt do
        {:ok,
         %{
           "publishNow" => false,
           "scheduledFor" => DateTime.to_iso8601(datetime),
           "timezone" => timezone
         }}
      else
        {:error, :schedule_in_past}
      end
    else
      _ -> {:error, :invalid_schedule}
    end
  end

  defp delivery_payload(%{"delivery" => "zernio_draft"}, _), do: {:ok, %{"isDraft" => true}}

  defp delivery_payload(%{"delivery" => "facebook_draft"}, _),
    do: {:ok, %{"publishNow" => true, "facebookSettings" => %{"draft" => true}}}

  defp delivery_payload(_, _), do: {:ok, %{"publishNow" => true}}

  defp local_to_utc(naive, "Asia/Dhaka"),
    do: DateTime.from_naive(NaiveDateTime.add(naive, -6, :hour), "Etc/UTC")

  defp local_to_utc(naive, _), do: DateTime.from_naive(naive, "Etc/UTC")

  defp validate_post(content, urls, type, media_type, params) do
    cond do
      String.length(content) > 63_206 ->
        {:error, :content_too_long}

      content == "" and urls == [] ->
        {:error, :content_required}

      type in ["story", "reel"] and urls == [] ->
        {:error, :media_required}

      type == "story" and length(urls) != 1 ->
        {:error, :single_media_required}

      type == "reel" and (length(urls) != 1 or media_type != "video") ->
        {:error, :single_video_required}

      media_type == "image" and length(urls) > 10 ->
        {:error, :too_many_images}

      media_type == "video" and length(urls) > 1 ->
        {:error, :single_video_required}

      truthy?(params["carousel"]) ->
        validate_carousel(params, urls, type, media_type)

      type == "story" ->
        :ok

      true ->
        validate_countries(params)
    end
  end

  defp validate_carousel(params, urls, type, media_type) do
    cards = carousel_cards(params["carousel_cards"])

    cond do
      type != "feed" or media_type != "image" ->
        {:error, :invalid_carousel_mode}

      length(urls) not in 2..5 ->
        {:error, :carousel_media_count}

      length(cards) != length(urls) ->
        {:error, :carousel_card_count}

      Enum.any?(cards, &(String.length(&1["name"] || "") > 255)) ->
        {:error, :carousel_field_too_long}

      Enum.any?(cards, &(String.length(&1["description"] || "") > 255)) ->
        {:error, :carousel_field_too_long}

      true ->
        validate_countries(params)
    end
  end

  defp validate_countries(params) do
    countries = split_csv(params["countries"])

    cond do
      truthy?(params["geo_enabled"]) and length(countries) > 25 ->
        {:error, :too_many_countries}

      truthy?(params["geo_enabled"]) and
          Enum.any?(countries, &(not Regex.match?(~r/^[A-Za-z]{2}$/, &1))) ->
        {:error, :invalid_country}

      true ->
        :ok
    end
  end

  defp put_carousel(map, params, urls, type, media_type) do
    if truthy?(params["carousel"]) and type == "feed" and media_type == "image" and
         length(urls) in 2..5 do
      cards = carousel_cards(params["carousel_cards"])

      map
      |> Map.put("carouselCards", cards)
      |> put_trimmed("carouselLink", params["carousel_link"])
    else
      map
    end
  end

  defp carousel_cards(value) do
    value
    |> parse_lines()
    |> Enum.map(fn line ->
      case String.split(line, "|", parts: 3) do
        [link, name, description] ->
          %{
            "link" => String.trim(link),
            "name" => String.trim(name),
            "description" => String.trim(description)
          }

        [link, name] ->
          %{"link" => String.trim(link), "name" => String.trim(name)}

        [link] ->
          %{"link" => String.trim(link)}
      end
    end)
  end

  defp normalize_post_params(params) do
    case {params["content_type"], params["delivery"]} do
      {"draft", _} -> Map.put(params, "delivery", "zernio_draft")
      {"story", "zernio_draft"} -> Map.put(params, "delivery", "now")
      {type, "zernio_draft"} when type != "draft" -> Map.put(params, "delivery", "now")
      _ -> params
    end
  end

  defp engagement_mutation(%{"action" => "hide", "post_id" => post, "id" => id}, socket),
    do: Facebook.hide_comment(post, id, account_id(socket))

  defp engagement_mutation(%{"action" => "unhide", "post_id" => post, "id" => id}, socket),
    do: Facebook.unhide_comment(post, id, account_id(socket))

  defp engagement_mutation(%{"action" => "like", "post_id" => post, "id" => id}, socket),
    do: Facebook.like_comment(post, id, account_id(socket))

  defp engagement_mutation(%{"action" => "unlike", "post_id" => post, "id" => id}, socket),
    do: Facebook.unlike_comment(post, id, account_id(socket))

  defp engagement_mutation(%{"action" => "delete", "post_id" => post, "id" => id}, socket),
    do: Facebook.delete_comment(post, id, accountId: account_id(socket))

  defp authorize(socket) do
    cond do
      not connected_account?(socket) -> {:error, :not_connected}
      not socket.assigns.manage_social -> {:error, :forbidden}
      true -> :ok
    end
  end

  defp mutation_result(socket, {:ok, _}, message, reload),
    do: socket |> put_flash(:info, message) |> reload.()

  defp mutation_result(socket, {:error, reason}, _message, _reload),
    do: put_flash(socket, :error, error_message(reason))

  defp api_value({:ok, value}), do: {value, nil}
  defp api_value({:error, reason}), do: {nil, error_message(reason)}

  defp assign_api_error(socket, reason, data) do
    if FacebookStudio.locked_error?(reason) do
      socket |> assign(:locked, true) |> assign(:data, data)
    else
      socket |> assign(:provider_error, error_message(reason)) |> assign(:data, data)
    end
  end

  defp items(nil, _), do: []

  defp items(value, key) when is_map(value),
    do: Map.get(value, key, Map.get(value, "data", [])) |> List.wrap()

  defp items(value, _) when is_list(value), do: value

  defp pagination_data(nil, fallback_page),
    do: %{"page" => positive_integer(fallback_page, 1), "pages" => 1, "total" => 0}

  defp pagination_data(value, fallback_page) do
    pagination = Map.get(value, "pagination", Map.get(value, "meta", %{}))

    %{
      "page" =>
        positive_integer(
          pagination["page"] || pagination["currentPage"] || fallback_page,
          1
        ),
      "pages" => positive_integer(pagination["pages"] || pagination["totalPages"], 1),
      "total" => non_negative_integer(pagination["total"], 0)
    }
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> default
    end
  end

  defp non_negative_integer(_value, default), do: default

  defp account_params(socket),
    do: [profileId: provider_profile_id(socket), accountId: account_id(socket)]

  defp provider_profile_id(socket),
    do: socket.assigns.social_profile && socket.assigns.social_profile.provider_profile_id

  defp account_id(socket),
    do: socket.assigns.facebook_account && socket.assigns.facebook_account.provider_account_id

  defp connected_account?(socket), do: not is_nil(account_id(socket))

  defp absolute_media_url("http" <> _ = url, _socket), do: url

  defp absolute_media_url(url, socket),
    do: AlgoieWeb.PublicURL.store(socket.assigns.store.slug, url)

  defp parse_lines(nil), do: []

  defp parse_lines(value),
    do:
      value
      |> to_string()
      |> String.split(~r/[\r\n]+/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  defp split_csv(nil), do: []

  defp split_csv(value),
    do: value |> String.split([",", "\n"], trim: true) |> Enum.map(&String.trim/1)

  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value, false), do: map

  defp put_trimmed(map, key, value) when is_binary(value),
    do: if(String.trim(value) == "", do: map, else: Map.put(map, key, String.trim(value)))

  defp put_trimmed(map, _key, _value), do: map

  defp put_countries(map, value) do
    countries =
      split_csv(value)
      |> Enum.map(&String.upcase/1)
      |> Enum.filter(&Regex.match?(~r/^[A-Z]{2}$/, &1))
      |> Enum.uniq()
      |> Enum.take(25)

    if countries == [], do: map, else: Map.put(map, "geoRestriction", %{"countries" => countries})
  end

  defp error_message({:provider_error, _status, body}), do: FacebookStudio.provider_error(body)
  defp error_message(:content_required), do: "Add post text or media."
  defp error_message(:content_too_long), do: "Facebook post text cannot exceed 63,206 characters."
  defp error_message(:media_required), do: "Stories and Reels require media."
  defp error_message(:single_media_required), do: "Stories require exactly one image or video."
  defp error_message(:single_video_required), do: "Use exactly one video for this format."
  defp error_message(:too_many_images), do: "Facebook supports up to 10 images."

  defp error_message(:invalid_carousel_mode),
    do: "Carousels require Feed or Draft mode with images."

  defp error_message(:carousel_media_count), do: "A carousel requires 2–5 images."

  defp error_message(:carousel_card_count),
    do: "Add exactly one carousel card row for each image."

  defp error_message(:carousel_field_too_long),
    do: "Carousel titles and descriptions have a 255-character hard limit."

  defp error_message(:too_many_countries), do: "Select no more than 25 countries."

  defp error_message(:invalid_country),
    do: "Countries must use two-letter ISO codes such as US or BD."

  defp error_message(:invalid_schedule), do: "Choose a valid schedule date and time."
  defp error_message(:schedule_in_past), do: "Schedule time must be in the future."
  defp error_message(:not_connected), do: "Connect a Facebook Page first."
  defp error_message(:forbidden), do: "You do not have permission to manage Facebook."
  defp error_message(%Jason.DecodeError{}), do: "Enter valid JSON."
  defp error_message(_), do: "Facebook could not complete that request."

  defp delivery_success("schedule"), do: "Facebook post scheduled"
  defp delivery_success("zernio_draft"), do: "Draft saved"
  defp delivery_success("facebook_draft"), do: "Facebook Publishing Tools draft created"
  defp delivery_success(_), do: "Post sent to Facebook"

  defp automation_form do
    to_form(
      %{
        "name" => "",
        "keywords" => "",
        "reply_message" => "",
        "dm_message" => "",
        "enabled" => true
      },
      as: :automation
    )
  end
end
