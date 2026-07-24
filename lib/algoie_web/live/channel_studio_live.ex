defmodule AlgoieWeb.ChannelStudioLive do
  use AlgoieWeb, :live_view

  alias Algoie.ChannelStudio.{Analytics, Content, Conversions, Inbox, MetaAds, WhatsApp}
  alias Algoie.ChannelStudio.Publishing.Composer
  alias AlgoieWeb.ChannelStudioContext

  @ranges ~w(7 30 90 180 365)
  @post_defaults %{
    "content" => "",
    "content_type" => "feed",
    "media_type" => "image",
    "media_urls" => "",
    "delivery" => "now",
    "scheduled_for" => "",
    "privacy_level" => "PUBLIC_TO_EVERYONE",
    "consent" => "false",
    "description" => "",
    "targets" => []
  }
  @template_defaults %{
    "name" => "",
    "category" => "UTILITY",
    "language" => "en_US",
    "body" => ""
  }
  @broadcast_defaults %{
    "name" => "",
    "template_name" => "",
    "template_language" => "en_US",
    "recipients" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> ChannelStudioContext.load()
      |> ChannelStudioContext.subscribe()
      |> assign(:page_title, "Channel Studio")
      |> assign(:manage_channels, ChannelStudioContext.manage?(socket))
      |> assign(:loading, false)
      |> assign(:provider_error, nil)
      |> assign(:data, %{})
      |> assign(:range, "30")
      |> assign(:post_errors, %{})
      |> assign(:post_form, to_form(@post_defaults, as: :studio_post))
      |> assign(:message_form, to_form(%{"message" => ""}, as: :message))
      |> assign(:comment_form, to_form(%{"message" => ""}, as: :comment_reply))
      |> assign(:template_form, to_form(@template_defaults, as: :template))
      |> assign(:broadcast_form, to_form(@broadcast_defaults, as: :broadcast))
      |> assign(
        :pixel_form,
        to_form(%{"name" => "", "ad_account_id" => "", "confirmed" => "false"},
          as: :pixel
        )
      )
      |> assign(:pixel_creating, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    send(self(), {:load_studio_action, socket.assigns.live_action, params})
    {:noreply, socket |> assign(:loading, true) |> assign(:provider_error, nil)}
  end

  @impl true
  def handle_event("validate-post", %{"studio_post" => params}, socket) do
    params = normalize_post_params(params)
    {_result, errors} = compose(params, socket)

    {:noreply,
     socket
     |> assign(:post_form, to_form(Map.merge(@post_defaults, params), as: :studio_post))
     |> assign(:post_errors, errors)}
  end

  def handle_event("publish", %{"studio_post" => params}, socket) do
    params = normalize_post_params(params)

    with :ok <- authorize(socket),
         {{:ok, payload}, _errors} <- compose(params, socket),
         {:ok, _response} <- Content.create(payload) do
      {:noreply,
       socket
       |> put_flash(:info, delivery_message(params["delivery"]))
       |> assign(:post_form, to_form(@post_defaults, as: :studio_post))
       |> assign(:post_errors, %{})}
    else
      {{:error, _}, errors} ->
        {:noreply,
         socket
         |> assign(:post_form, to_form(Map.merge(@post_defaults, params), as: :studio_post))
         |> assign(:post_errors, errors)}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("change-range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, push_patch(socket, to: ~p"/dashboard/studio/analytics?range=#{range}")}
  end

  def handle_event("select-conversation", %{"id" => id}, socket) do
    send(self(), {:load_studio_conversation, id})

    {:noreply,
     socket
     |> assign(:loading, true)
     |> update(:data, &Map.merge(&1, %{selected_conversation: id, messages: []}))}
  end

  def handle_event("select-comment-post", %{"id" => id, "account-id" => account_id}, socket) do
    send(self(), {:load_studio_comments, id, account_id})

    {:noreply,
     socket
     |> assign(:loading, true)
     |> update(
       :data,
       &Map.merge(&1, %{selected_comment_post: id, comment_account_id: account_id, comments: []})
     )}
  end

  def handle_event("send-message", %{"message" => %{"message" => message}}, socket) do
    id = socket.assigns.data[:selected_conversation]
    conversation = selected_conversation(socket.assigns.data[:conversations] || [], id)
    account_id = conversation_account_id([conversation], id)
    platform = conversation_platform(conversation)

    payload = %{
      "message" => String.trim(message),
      "accountId" => account_id,
      "profileId" => profile_id(socket),
      "platform" => platform
    }

    result =
      cond do
        not socket.assigns.manage_channels -> {:error, :forbidden}
        is_nil(id) -> {:error, :conversation_required}
        payload["message"] == "" -> {:error, :message_required}
        platform not in ["facebook", "instagram", "whatsapp"] -> {:error, :unsupported_platform}
        true -> Inbox.send_message(id, payload)
      end

    case result do
      {:ok, _response} ->
        send(self(), {:load_studio_conversation, id})

        {:noreply,
         socket
         |> assign(:message_form, to_form(%{"message" => ""}, as: :message))
         |> assign(:provider_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("reply-comment", %{"comment_reply" => %{"message" => message}}, socket) do
    post_id = socket.assigns.data[:selected_comment_post]
    account_id = socket.assigns.data[:comment_account_id]
    message = String.trim(message)

    result =
      cond do
        not socket.assigns.manage_channels -> {:error, :forbidden}
        is_nil(post_id) or is_nil(account_id) -> {:error, :comment_post_required}
        message == "" -> {:error, :message_required}
        true -> Inbox.reply(post_id, %{"accountId" => account_id, "message" => message})
      end

    case result do
      {:ok, _response} ->
        send(self(), {:load_studio_comments, post_id, account_id})

        {:noreply,
         socket
         |> assign(:comment_form, to_form(%{"message" => ""}, as: :comment_reply))
         |> assign(:provider_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("post-action", %{"action" => action, "id" => id}, socket)
      when action in ["retry", "delete"] do
    result =
      with :ok <- authorize(socket) do
        if action == "retry", do: Content.retry(id), else: Content.delete(id)
      end

    case result do
      {:ok, _response} ->
        send(self(), {:load_studio_action, socket.assigns.live_action, %{}})
        message = if action == "retry", do: "Post queued for retry", else: "Post deleted"
        {:noreply, socket |> assign(:loading, true) |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("connect-meta-ads", %{"platform" => platform}, socket)
      when platform in ["facebook", "instagram"] do
    parent = ChannelStudioContext.account(socket, platform)

    result =
      if socket.assigns.manage_channels && parent && socket.assigns.social_profile do
        MetaAds.connect(
          socket.assigns.social_profile.provider_profile_id,
          parent.provider_account_id,
          platform,
          AlgoieWeb.PublicURL.store(socket.assigns.store.slug, "/dashboard/social/callback")
        )
      else
        if not socket.assigns.manage_channels do
          {:error, :forbidden}
        else
          {:error, :parent_account_required}
        end
      end

    case result do
      {:ok, %{"authUrl" => url}} when is_binary(url) ->
        {:noreply, redirect(socket, external: url)}

      {:ok, _} ->
        {:noreply,
         put_flash(socket, :info, "Meta Ads connected. Refreshing accounts may take a moment.")}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("create-template", %{"template" => params}, socket) do
    account_id = ChannelStudioContext.account_id(socket, "whatsapp")
    name = params["name"] |> to_string() |> String.trim()
    body = params["body"] |> to_string() |> String.trim()

    result =
      cond do
        not socket.assigns.manage_channels ->
          {:error, :forbidden}

        is_nil(account_id) ->
          {:error, :whatsapp_required}

        not Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) ->
          {:error, :template_name_invalid}

        body == "" ->
          {:error, :template_body_required}

        true ->
          WhatsApp.create_template(%{
            "accountId" => account_id,
            "name" => name,
            "category" => params["category"],
            "language" => params["language"],
            "components" => [%{"type" => "BODY", "text" => body}]
          })
      end

    case result do
      {:ok, _response} ->
        {:noreply,
         socket
         |> assign(:template_form, to_form(@template_defaults, as: :template))
         |> load_whatsapp()
         |> put_flash(:info, "Template submitted to WhatsApp for review")}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("create-broadcast", %{"broadcast" => params}, socket) do
    account_id = ChannelStudioContext.account_id(socket, "whatsapp")
    name = params["name"] |> to_string() |> String.trim()
    template_name = params["template_name"] |> to_string() |> String.trim()
    recipients = parse_recipients(params["recipients"])

    result =
      cond do
        not socket.assigns.manage_channels -> {:error, :forbidden}
        is_nil(account_id) -> {:error, :whatsapp_required}
        name == "" -> {:error, :broadcast_name_required}
        template_name == "" -> {:error, :broadcast_template_required}
        recipients == [] -> {:error, :broadcast_recipients_required}
        true -> create_whatsapp_broadcast(socket, account_id, params, recipients)
      end

    case result do
      {:ok, broadcast} ->
        {:noreply,
         socket
         |> assign(:broadcast_form, to_form(@broadcast_defaults, as: :broadcast))
         |> load_whatsapp()
         |> put_flash(:info, "Broadcast draft created with #{length(recipients)} recipients")
         |> update(:data, &Map.put(&1, :created_broadcast, broadcast))}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("send-broadcast", %{"id" => id}, socket) do
    result = with :ok <- authorize(socket), do: WhatsApp.send_broadcast(id)

    case result do
      {:ok, _response} ->
        {:noreply, socket |> load_whatsapp() |> put_flash(:info, "Broadcast sending started")}

      {:error, reason} ->
        {:noreply, assign(socket, :provider_error, error_message(reason))}
    end
  end

  def handle_event("create-pixel", %{"pixel" => params}, socket) do
    account_id = ChannelStudioContext.account_id(socket, "metaads")
    name = String.trim(params["name"] || "")
    ad_account_id = String.trim(params["ad_account_id"] || "")

    result =
      cond do
        not socket.assigns.manage_channels ->
          {:error, :forbidden}

        is_nil(account_id) ->
          {:error, :meta_ads_required}

        name == "" ->
          {:error, :pixel_name_required}

        ad_account_id == "" ->
          {:error, :ad_account_required}

        params["confirmed"] not in ["true", "on", true] ->
          {:error, :pixel_confirmation_required}

        true ->
          Conversions.create_pixel(account_id, %{"name" => name, "adAccountId" => ad_account_id})
      end

    case result do
      {:ok, response} ->
        {:noreply,
         socket
         |> update(:data, &Map.put(&1, :created_pixel, response["tag"] || response))
         |> assign(
           :pixel_form,
           to_form(%{"name" => "", "ad_account_id" => "", "confirmed" => "false"}, as: :pixel)
         )
         |> assign(:pixel_creating, false)
         |> assign(:provider_error, nil)
         |> put_flash(:info, "Meta Pixel created. Install its code before expecting events.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:pixel_creating, false)
         |> assign(:provider_error, error_message(reason))}
    end
  end

  @impl true
  def handle_info({:load_studio_action, action, params}, socket) do
    if action == socket.assigns.live_action do
      {:noreply, socket |> load_action(params) |> assign(:loading, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:load_studio_conversation, id}, socket) do
    if socket.assigns.data[:selected_conversation] == id do
      account_id = conversation_account_id(socket.assigns.data[:conversations] || [], id)

      case Inbox.messages(id, accountId: account_id, limit: 50, sortOrder: "asc") do
        {:ok, response} ->
          if socket.assigns.manage_channels, do: Inbox.mark_read(id, account_id)

          {:noreply,
           socket
           |> update(:data, &Map.put(&1, :messages, items(response, "messages")))
           |> assign(:loading, false)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:provider_error, error_message(reason))
           |> assign(:loading, false)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:load_studio_comments, post_id, account_id}, socket) do
    if socket.assigns.data[:selected_comment_post] == post_id do
      case Inbox.comments(post_id, accountId: account_id, limit: 50) do
        {:ok, response} ->
          {:noreply,
           socket
           |> update(:data, &Map.put(&1, :comments, items(response, "comments")))
           |> assign(:loading, false)}

        {:error, reason} ->
          {:noreply,
           socket |> assign(:provider_error, error_message(reason)) |> assign(:loading, false)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:zernio_event, payload}, socket) do
    if relevant_event?(payload, socket.assigns.live_action) do
      send(self(), {:load_studio_action, socket.assigns.live_action, %{}})
      {:noreply, assign(socket, :loading, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def platform_name(:metaads), do: "Meta Ads"

  def platform_name(platform) when is_atom(platform),
    do: platform |> Atom.to_string() |> platform_name()

  def platform_name("tiktok"), do: "TikTok"
  def platform_name("whatsapp"), do: "WhatsApp"
  def platform_name(platform), do: String.capitalize(platform)

  def account_name(account) do
    metadata = account.metadata || %{}

    metadata["name"] || metadata["username"] || metadata["pageName"] ||
      metadata["phoneNumber"] || platform_name(account.platform)
  end

  def account_connected?(account), do: ChannelStudioContext.connected?(account)
  def account_id(account), do: account.provider_account_id
  def post_id(post), do: post["_id"] || post["id"]
  def conversation_id(conversation), do: conversation["_id"] || conversation["id"]
  def comment_post_id(post), do: post["postId"] || post["_id"] || post["id"]
  def comment_account_id(post), do: post["accountId"] || get_in(post, ["account", "_id"])

  def comment_author(comment),
    do: get_in(comment, ["from", "name"]) || get_in(comment, ["from", "username"]) || "Customer"

  def ad_campaigns(tree) when is_map(tree),
    do: tree["campaigns"] || get_in(tree, ["data", "campaigns"]) || tree["data"] || []

  def ad_campaigns(_tree), do: []

  def campaign_name(campaign),
    do: campaign["name"] || campaign["campaignName"] || "Untitled campaign"

  def campaign_status(campaign),
    do: campaign["effectiveStatus"] || campaign["status"] || "unknown"

  def template_body(template) do
    template
    |> Map.get("components", [])
    |> Enum.find_value(fn component ->
      if component["type"] in ["BODY", "body"], do: component["text"]
    end)
  end

  def tiktok_privacy_options(data) do
    data
    |> get_in([:tiktok_creator, "privacyLevels"])
    |> List.wrap()
    |> Enum.map(fn
      %{"value" => value, "label" => label} ->
        {label, value}

      %{"value" => value} ->
        {value, value}

      value when is_binary(value) ->
        {value |> String.replace("_", " ") |> String.capitalize(), value}
    end)
  end

  def participant_name(conversation) do
    conversation["participantName"] || get_in(conversation, ["participant", "name"]) ||
      conversation["name"] || "Customer"
  end

  def message_text(message),
    do: message["message"] || message["text"] || message["content"] || "Attachment"

  def post_error(errors, platform, field) do
    errors
    |> Map.get(platform, [])
    |> Enum.filter(fn {error_field, _message} -> error_field == field end)
    |> Enum.map_join(" · ", &elem(&1, 1))
  end

  def selected_target?(form, account) do
    value = "#{account.platform}:#{account.provider_account_id}"
    value in List.wrap(form[:targets].value)
  end

  attr :platform, :atom, required: true
  attr :account, :any, default: nil

  def channel_card(assigns) do
    ~H"""
    <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
      <div class="flex items-start justify-between gap-3">
        <span class="flex size-10 items-center justify-center rounded-xl bg-slate-100 text-slate-600">
          <.icon name="hero-share" class="size-5" />
        </span>
        <span class={[
          "rounded-full px-2 py-1 text-[10px] font-bold uppercase tracking-wide",
          @account && account_connected?(@account) && "bg-emerald-50 text-emerald-700",
          (!@account || !account_connected?(@account)) && "bg-slate-100 text-slate-500"
        ]}>
          {if @account && account_connected?(@account), do: "Connected", else: "Not connected"}
        </span>
      </div>
      <h2 class="mt-4 font-bold">{platform_name(@platform)}</h2>
      <p class="mt-1 truncate text-xs text-slate-500">
        {if @account, do: account_name(@account), else: "Connect from Channels"}
      </p>
    </article>
    """
  end

  attr :data, :map, required: true

  def metric_grid(assigns) do
    overview = assigns.data["overview"] || assigns.data["totals"] || assigns.data
    assigns = assign(assigns, :overview, overview)

    ~H"""
    <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <.summary_card
        title="Impressions"
        value={metric_value(@overview, "impressions")}
        icon="hero-eye"
      />
      <.summary_card title="Likes" value={metric_value(@overview, "likes")} icon="hero-heart" />
      <.summary_card
        title="Comments"
        value={metric_value(@overview, "comments")}
        icon="hero-chat-bubble-left"
      />
      <.summary_card
        title="Shares"
        value={metric_value(@overview, "shares")}
        icon="hero-arrow-path-rounded-square"
      />
      <.summary_card
        title="Clicks"
        value={metric_value(@overview, "clicks")}
        icon="hero-cursor-arrow-rays"
      />
      <.summary_card title="Views" value={metric_value(@overview, "views")} icon="hero-play" />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true

  def summary_card(assigns) do
    ~H"""
    <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div class="flex items-center justify-between gap-3">
        <p class="text-sm font-medium text-slate-500">{@title}</p>
        <.icon name={@icon} class="size-5 text-slate-300" />
      </div>
      <p class="mt-3 text-2xl font-bold tracking-tight">{@value}</p>
    </article>
    """
  end

  attr :title, :string, required: true
  attr :data, :any, default: nil
  attr :metrics, :list, required: true

  def insight_panel(assigns) do
    ~H"""
    <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <h2 class="font-bold">{@title}</h2>
      <div
        :if={is_nil(@data)}
        class="mt-5 rounded-xl bg-slate-50 p-5 text-center text-sm text-slate-400"
      >
        Account not connected or insights unavailable.
      </div>
      <dl :if={@data} class="mt-4 grid grid-cols-2 gap-3">
        <div :for={{label, key} <- @metrics} class="rounded-xl bg-slate-50 p-3">
          <dt class="text-xs text-slate-500">{label}</dt>
          <dd class="mt-1 text-lg font-bold">{insight_value(@data, key)}</dd>
        </div>
      </dl>
    </article>
    """
  end

  defp metric_value(data, key) when is_map(data), do: data[key] || "—"
  defp metric_value(_data, _key), do: "—"

  defp insight_value(data, key) do
    get_in(data, ["metrics", key, "total"]) ||
      get_in(data, ["metrics", key, "total_value", "value"]) ||
      data[key] || get_in(data, ["data", key]) || "—"
  end

  defp load_action(socket, params) do
    case socket.assigns.live_action do
      :index -> load_overview(socket)
      :create -> load_composer(socket)
      :posts -> load_posts(socket, params)
      :calendar -> load_posts(socket, Map.put(params, "limit", "100"))
      :messages -> load_messages(socket, params)
      :comments -> load_comments(socket, params)
      :analytics -> load_analytics(socket, params)
      :ads -> load_ads(socket, params)
      :whatsapp -> load_whatsapp(socket)
      :conversions -> load_conversions(socket)
      _ -> socket
    end
  end

  defp load_overview(socket) do
    assign(socket, :data, %{capabilities: Algoie.ChannelStudio.Capabilities.all()})
  end

  defp load_composer(socket) do
    case ChannelStudioContext.account_id(socket, "tiktok") do
      nil ->
        assign(socket, :data, %{})

      id ->
        assign_result(
          socket,
          Algoie.ChannelStudio.Publishing.Tiktok.creator_info(id, "video"),
          :tiktok_creator,
          nil
        )
    end
  end

  defp load_posts(socket, params) do
    query =
      [
        profileId: profile_id(socket),
        platform: params["platform"],
        status: params["status"],
        page: params["page"] || 1,
        limit: params["limit"] || 20
      ]

    assign_result(socket, Content.list(query), :posts, "posts")
  end

  defp load_messages(socket, params) do
    query = [profileId: profile_id(socket), platform: params["platform"], limit: 30]
    assign_result(socket, Inbox.conversations(query), :conversations, "conversations")
  end

  defp load_comments(socket, params) do
    query = [profileId: profile_id(socket), platform: params["platform"], limit: 30]
    assign_result(socket, Inbox.commented_posts(query), :comment_posts, "posts")
  end

  defp load_analytics(socket, params) do
    range = if params["range"] in @ranges, do: params["range"], else: "30"
    days = String.to_integer(range)
    to = Date.utc_today()
    from = Date.add(to, -(days - 1))

    query = [
      profileId: profile_id(socket),
      platform: params["platform"],
      fromDate: Date.to_iso8601(from),
      toDate: Date.to_iso8601(to)
    ]

    insight_from = Date.add(to, -(min(days, 89) - 1))
    insight_dates = [since: Date.to_iso8601(insight_from), until: Date.to_iso8601(to)]

    requests = [
      analytics: fn -> Analytics.overview(query) end,
      facebook_insights: fn ->
        request_if_account(socket, "facebook", &Analytics.facebook_page(&1, insight_dates))
      end,
      instagram_insights: fn ->
        request_if_account(socket, "instagram", &Analytics.instagram_account(&1, insight_dates))
      end,
      instagram_followers: fn ->
        request_if_account(socket, "instagram", &Analytics.instagram_followers(&1, insight_dates))
      end,
      tiktok_insights: fn ->
        request_if_account(socket, "tiktok", fn id ->
          Analytics.tiktok_account(id,
            fromDate: Date.to_iso8601(from),
            toDate: Date.to_iso8601(to)
          )
        end)
      end
    ]

    data =
      requests
      |> Task.async_stream(fn {key, request} -> {key, request.()} end,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn
        {:ok, {key, {:ok, value}}}, acc -> Map.put(acc, key, value)
        _result, acc -> acc
      end)

    socket |> assign(:range, range) |> assign(:data, data)
  end

  defp load_ads(socket, params) do
    case ChannelStudioContext.account_id(socket, "metaads") do
      nil ->
        assign(socket, :data, %{})

      id ->
        assign_result(
          socket,
          MetaAds.tree(accountId: id, limit: params["limit"] || 50),
          :ad_tree,
          nil
        )
    end
  end

  defp load_whatsapp(socket) do
    case ChannelStudioContext.account_id(socket, "whatsapp") do
      nil ->
        assign(socket, :data, %{})

      id ->
        socket
        |> assign_result(WhatsApp.number_info(id), :number_info, nil)
        |> merge_result(WhatsApp.templates(id), :templates, "templates")
        |> merge_result(
          WhatsApp.broadcasts(profileId: profile_id(socket), platform: "whatsapp"),
          :broadcasts,
          "broadcasts"
        )
    end
  end

  defp load_conversions(socket) do
    case ChannelStudioContext.account_id(socket, "metaads") do
      nil ->
        assign(socket, :data, %{})

      id ->
        socket
        |> assign_result(Conversions.pixels(id), :pixels, "tags")
        |> merge_result(MetaAds.accounts(id), :ad_accounts, "accounts")
    end
  end

  defp assign_result(socket, {:ok, response}, key, item_key) do
    value = if item_key, do: items(response, item_key), else: response

    assign(socket, :data, %{
      key => value,
      provider_meta: if(is_map(response), do: response["meta"], else: nil)
    })
  end

  defp assign_result(socket, {:error, reason}, _key, _item_key) do
    socket |> assign(:data, %{}) |> assign(:provider_error, error_message(reason))
  end

  defp merge_result(socket, {:ok, response}, key, item_key) do
    value = if item_key, do: items(response, item_key), else: response

    update(socket, :data, fn data ->
      data
      |> Map.put(key, value)
      |> Map.put_new(:provider_meta, if(is_map(response), do: response["meta"], else: nil))
    end)
  end

  defp merge_result(socket, {:error, _reason}, _key, _item_key), do: socket

  defp compose(params, socket) do
    with {:ok, params} <- normalize_delivery(params, socket.assigns.store) do
      post =
        params
        |> Map.put("media_items", media_items(params))
        |> put_platform_content_types()

      targets = parse_targets(params["targets"], socket.assigns.channel_accounts)

      case Composer.build(post, targets) do
        {:ok, payload} -> {{:ok, payload}, %{}}
        {:error, errors} -> {{:error, errors}, errors}
      end
    else
      {:error, message} -> {{:error, :invalid_schedule}, %{delivery: [{:scheduled_for, message}]}}
    end
  end

  defp normalize_delivery(%{"delivery" => "schedule", "scheduled_for" => value} = params, store) do
    value = to_string(value)

    with true <- value != "",
         {:ok, naive} <-
           NaiveDateTime.from_iso8601(
             value <> if(String.length(value) == 16, do: ":00", else: "")
           ),
         {:ok, datetime} <- local_to_utc(naive, store && store.timezone),
         :gt <- DateTime.compare(datetime, DateTime.utc_now()) do
      {:ok, Map.put(params, "scheduled_for", DateTime.to_iso8601(datetime))}
    else
      :lt -> {:error, "Choose a future publishing time"}
      :eq -> {:error, "Choose a future publishing time"}
      _ -> {:error, "Choose a valid publishing time"}
    end
  end

  defp normalize_delivery(params, _store), do: {:ok, params}

  defp local_to_utc(naive, "Asia/Dhaka"),
    do: DateTime.from_naive(NaiveDateTime.add(naive, -6, :hour), "Etc/UTC")

  defp local_to_utc(naive, _timezone), do: DateTime.from_naive(naive, "Etc/UTC")

  defp put_platform_content_types(%{"content_type" => "reel"} = post) do
    Map.put(post, "platform_overrides", %{"instagram" => %{"content_type" => "reels"}})
  end

  defp put_platform_content_types(post), do: post

  defp media_items(params) do
    params["media_urls"]
    |> to_string()
    |> String.split(["\n", ","], trim: true)
    |> Enum.map(&%{"type" => params["media_type"] || "image", "url" => String.trim(&1)})
  end

  defp parse_targets(values, accounts) do
    allowed = Map.new(accounts, &{"#{&1.platform}:#{&1.provider_account_id}", &1})

    values
    |> List.wrap()
    |> Enum.flat_map(fn value ->
      case allowed[value] do
        nil ->
          []

        account ->
          [
            %{
              "platform" => Atom.to_string(account.platform),
              "account_id" => account.provider_account_id
            }
          ]
      end
    end)
  end

  defp normalize_post_params(params), do: Map.update(params, "targets", [], &List.wrap/1)
  defp authorize(%{assigns: %{manage_channels: true}}), do: :ok
  defp authorize(_socket), do: {:error, :forbidden}
  defp profile_id(%{assigns: %{social_profile: %{provider_profile_id: id}}}), do: id
  defp profile_id(_socket), do: nil

  defp items(response, key) when is_map(response) do
    case Map.get(response, key) do
      items when is_list(items) -> items
      _ -> if is_list(response["data"]), do: response["data"], else: []
    end
  end

  defp items(_response, _key), do: []

  defp request_if_account(socket, platform, request) do
    case ChannelStudioContext.account_id(socket, platform) do
      nil -> {:ok, nil}
      id -> request.(id)
    end
  end

  defp conversation_account_id(conversations, id) do
    conversation = Enum.find(conversations, &(conversation_id(&1) == id)) || %{}
    conversation["accountId"] || get_in(conversation, ["account", "_id"])
  end

  defp selected_conversation(conversations, id) do
    Enum.find(conversations, &(conversation_id(&1) == id)) || %{}
  end

  defp conversation_platform(conversation) do
    conversation["platform"] || get_in(conversation, ["account", "platform"])
  end

  defp parse_recipients(value) do
    value
    |> to_string()
    |> String.split(["\n", ","], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(~r/^\+?[1-9]\d{6,14}$/, &1))
    |> Enum.uniq()
  end

  defp create_whatsapp_broadcast(socket, account_id, params, recipients) do
    payload = %{
      "profileId" => profile_id(socket),
      "accountId" => account_id,
      "platform" => "whatsapp",
      "name" => String.trim(params["name"]),
      "template" => %{
        "name" => String.trim(params["template_name"]),
        "language" => params["template_language"] || "en_US",
        "components" => []
      }
    }

    with {:ok, response} <- WhatsApp.create_broadcast(payload),
         broadcast when is_map(broadcast) <- response["broadcast"] || response,
         id when is_binary(id) <- broadcast["id"] || broadcast["_id"],
         {:ok, _response} <- WhatsApp.add_recipients(id, recipients) do
      {:ok, broadcast}
    else
      nil -> {:error, :invalid_provider_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp relevant_event?(payload, action) do
    event = payload["event"] || payload["type"] || ""

    case action do
      action when action in [:messages, :comments] ->
        String.starts_with?(event, ["message.", "comment."])

      action when action in [:posts, :calendar] ->
        String.starts_with?(event, "post.")

      :ads ->
        String.starts_with?(event, ["ad.", "campaign.", "lead."])

      _ ->
        String.starts_with?(event, "account.")
    end
  end

  defp delivery_message("schedule"), do: "Post scheduled"
  defp delivery_message("draft"), do: "Draft saved"
  defp delivery_message(_), do: "Post submitted for publishing"

  defp error_message({:provider_error, _status, %{"error" => error}}), do: error
  defp error_message({:provider_error, _status, %{"message" => message}}), do: message
  defp error_message(:forbidden), do: "You do not have permission to manage channels."

  defp error_message(:parent_account_required),
    do: "Connect Facebook or Instagram before connecting Meta Ads."

  defp error_message(:conversation_required), do: "Select a conversation before replying."
  defp error_message(:message_required), do: "Write a message before sending."
  defp error_message(:comment_post_required), do: "Select a post before replying."
  defp error_message(:unsupported_platform), do: "This channel does not support direct messages."
  defp error_message(:meta_ads_required), do: "Connect Meta Ads before creating a Pixel."
  defp error_message(:whatsapp_required), do: "Connect WhatsApp before using this feature."

  defp error_message(:template_name_invalid),
    do:
      "Template names must start with a letter and contain lowercase letters, numbers, or underscores."

  defp error_message(:template_body_required), do: "Enter the template message body."
  defp error_message(:broadcast_name_required), do: "Enter a broadcast name."
  defp error_message(:broadcast_template_required), do: "Choose an approved WhatsApp template."

  defp error_message(:broadcast_recipients_required),
    do: "Add at least one valid international phone number."

  defp error_message(:pixel_name_required), do: "Enter a name for the Meta Pixel."

  defp error_message(:ad_account_required),
    do: "Choose the Meta ad account that will own this Pixel."

  defp error_message(:pixel_confirmation_required),
    do: "Confirm that Pixel creation cannot be undone before continuing."

  defp error_message(_reason), do: "The channel provider could not complete this request."
end
