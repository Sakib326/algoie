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
    "carousel_cards" => ""
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
  def handle_params(params, _uri, socket), do: {:noreply, load_action(socket, params)}

  @impl true
  def handle_event("validate-post", %{"facebook_post" => params}, socket) do
    {:noreply,
     assign(socket, :post_form, to_form(Map.merge(@post_defaults, params), as: :facebook_post))}
  end

  def handle_event("publish", %{"facebook_post" => params}, socket) do
    with :ok <- authorize(socket),
         {:ok, payload} <- build_post_payload(params, socket),
         {:ok, _} <- Facebook.create_post(payload) do
      {:noreply,
       socket
       |> assign(:post_form, to_form(@post_defaults, as: :facebook_post))
       |> put_flash(:info, delivery_success(params["delivery"]))}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
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

    {:noreply, mutation_result(socket, result, "Post updated", &load_posts(&1, %{}))}
  end

  def handle_event("filter-posts", %{"filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/facebook/posts?#{params}")}
  end

  def handle_event("select-conversation", %{"id" => id}, socket) do
    {:noreply, load_conversation(socket, id)}
  end

  def handle_event("send-message", %{"message" => params}, socket) do
    id = socket.assigns.data[:selected_conversation]

    payload =
      %{"message" => String.trim(params["message"] || "")}
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
    result = engagement_mutation(params)

    {:noreply,
     mutation_result(socket, result, "Facebook engagement updated", &load_engagement(&1, %{}))}
  end

  def handle_event(
        "reply",
        %{"reply" => %{"message" => message}, "kind" => kind, "entity_id" => id} = params,
        socket
      ) do
    result =
      case kind do
        "comment" ->
          Facebook.reply_to_comment(params["post_id"], %{"commentId" => id, "message" => message})

        "review" ->
          Facebook.reply_to_review(id, %{"message" => message})

        "private" ->
          Facebook.private_reply(params["post_id"], id, %{"message" => message})
      end

    {:noreply,
     mutation_result(socket, result, "Reply sent", fn updated ->
       updated
       |> assign(:reply_form, to_form(%{"message" => ""}, as: :reply))
       |> load_engagement(%{})
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
  def handle_info({:zernio_event, _event}, socket), do: {:noreply, load_action(socket, %{})}

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

  defp load_action(socket, params) do
    socket = socket |> assign(:locked, false) |> assign(:provider_error, nil)

    case socket.assigns.live_action do
      :index -> load_overview(socket)
      :publishing -> load_publishing(socket)
      :posts -> load_posts(socket, params)
      :analytics -> load_analytics(socket, params)
      :inbox -> load_inbox(socket, params)
      :engagement -> load_engagement(socket, params)
      :automations -> load_automations(socket)
      :settings -> load_settings(socket)
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
            status: params["status"],
            search: params["search"]
          ]

      {response, error} = api_value(Facebook.list_posts(query))

      assign(socket, :data, %{
        posts: items(response, "posts"),
        pagination: pagination_data(response),
        filters: params,
        error: error
      })
    else
      assign(socket, :data, %{})
    end
  end

  defp load_analytics(socket, params) do
    if connected_account?(socket) do
      from = params["from"] || Date.to_iso8601(Date.add(Date.utc_today(), -30))
      to = params["to"] || Date.to_iso8601(Date.utc_today())
      result = Facebook.analytics(account_params(socket) ++ [fromDate: from, toDate: to])
      insights = Facebook.page_insights(account_id(socket), fromDate: from, toDate: to)

      case {result, insights} do
        {{:ok, analytics}, {:ok, page}} ->
          assign(socket, :data, %{analytics: analytics, insights: page, from: from, to: to})

        {{:error, reason}, _} ->
          assign_api_error(socket, reason, %{from: from, to: to})

        {_, {:error, reason}} ->
          assign_api_error(socket, reason, %{from: from, to: to})
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

  defp load_conversation(socket, nil), do: socket

  defp load_conversation(socket, id) do
    {response, error} = api_value(Facebook.messages(id, limit: 100))

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
    media_type = params["media_type"] || "image"

    with :ok <- validate_post(content, urls, content_type, media_type),
         {:ok, delivery} <- delivery_payload(params, socket.assigns.store.timezone) do
      specific =
        %{}
        |> maybe_put("contentType", content_type, content_type != "feed")
        |> put_trimmed("title", params["title"])
        |> put_trimmed("firstComment", params["first_comment"])
        |> put_countries(params["countries"])
        |> put_carousel(params, urls)

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
        "content" => content,
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
      {:ok,
       %{
         "publishNow" => false,
         "scheduledFor" => DateTime.to_iso8601(datetime),
         "timezone" => timezone
       }}
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

  defp validate_post("", [], _, _), do: {:error, :content_required}
  defp validate_post(_, [], type, _) when type in ["story", "reel"], do: {:error, :media_required}
  defp validate_post(_, [_], "reel", "video"), do: :ok
  defp validate_post(_, _, "reel", _), do: {:error, :single_video_required}
  defp validate_post(_, urls, _, "image") when length(urls) > 10, do: {:error, :too_many_images}

  defp validate_post(_, urls, _, "video") when length(urls) > 1,
    do: {:error, :single_video_required}

  defp validate_post(_, _, _, _), do: :ok

  defp put_carousel(map, params, urls) do
    if truthy?(params["carousel"]) and length(urls) in 2..5 do
      cards =
        params["carousel_cards"]
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

      map
      |> Map.put("carouselCards", cards)
      |> put_trimmed("carouselLink", params["carousel_link"])
    else
      map
    end
  end

  defp engagement_mutation(%{"action" => "hide", "post_id" => post, "id" => id}),
    do: Facebook.hide_comment(post, id)

  defp engagement_mutation(%{"action" => "unhide", "post_id" => post, "id" => id}),
    do: Facebook.unhide_comment(post, id)

  defp engagement_mutation(%{"action" => "like", "post_id" => post, "id" => id}),
    do: Facebook.like_comment(post, id)

  defp engagement_mutation(%{"action" => "unlike", "post_id" => post, "id" => id}),
    do: Facebook.unlike_comment(post, id)

  defp engagement_mutation(%{"action" => "delete", "post_id" => post, "id" => id}),
    do: Facebook.delete_comment(post, id)

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
  defp pagination_data(nil), do: %{}
  defp pagination_data(value), do: Map.get(value, "pagination", Map.get(value, "meta", %{}))

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
  defp error_message(:media_required), do: "Stories and Reels require media."
  defp error_message(:single_video_required), do: "Use exactly one video for this format."
  defp error_message(:too_many_images), do: "Facebook supports up to 10 images."
  defp error_message(:invalid_schedule), do: "Choose a valid schedule date and time."
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
