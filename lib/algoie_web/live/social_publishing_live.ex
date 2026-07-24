defmodule AlgoieWeb.SocialPublishingLive do
  use AlgoieWeb, :live_view
  alias Algoie.SocialPublishing
  alias Algoie.SocialPublishing.SocialAccount
  require Ash.Query
  alias Algoie.Stores.Store

  @oauth_platforms ~w(facebook instagram whatsapp tiktok)
  @account_platforms @oauth_platforms ++ ~w(metaads)

  def mount(_params, _session, socket) do
    case Ash.get(Store, socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, store} ->
        {:ok,
         socket
         |> assign(:store, store)
         |> assign(:page_title, "Social publishing")
         |> assign(:platforms, @oauth_platforms)
         |> assign(:available_platforms, @oauth_platforms)
         |> assign(:facebook_connection, nil)
         |> assign(:facebook_pages, [])
         |> load_social()}

      _ ->
        {:ok, redirect(socket, to: "/dashboard")}
    end
  end

  def handle_params(
        %{
          "platform" => "facebook",
          "step" => "select_page",
          "profileId" => profile_id,
          "tempToken" => temp_token,
          "userProfile" => encoded_user_profile
        } = params,
        _uri,
        %{assigns: %{live_action: :callback}} = socket
      ) do
    with %{provider_profile_id: ^profile_id} <- socket.assigns.social_profile,
         {:ok, user_profile} <- decode_user_profile(encoded_user_profile),
         {:ok, pages} <- SocialPublishing.list_facebook_pages(profile_id, temp_token) do
      {:noreply,
       socket
       |> assign(:page_title, "Choose a Facebook Page")
       |> assign(:facebook_pages, pages)
       |> assign(:facebook_connection, %{
         profile_id: profile_id,
         temp_token: temp_token,
         user_profile: user_profile,
         connect_token: params["connect_token"]
       })}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not load your Facebook Pages. Please reconnect.")
         |> push_navigate(to: ~p"/dashboard/social")}
    end
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :callback}} = socket) do
    case socket.assigns.social_profile do
      nil ->
        {:noreply, put_flash(socket, :error, "Social profile was not found")}

      profile ->
        case SocialPublishing.sync_accounts(profile, AlgoieWeb.Scope.opts(socket)) do
          {:ok, _} ->
            {:noreply, socket |> load_social() |> put_flash(:info, "Social account connected")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not synchronize the connected account")}
        end
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("connect", %{"platform" => platform}, socket)
      when platform in @oauth_platforms do
    if connected_platform?(socket.assigns.social_accounts, platform) do
      {:noreply, put_flash(socket, :info, "#{platform_name(platform)} is already connected")}
    else
      with {:ok, profile} <-
             SocialPublishing.get_or_create_profile(
               socket.assigns.store,
               AlgoieWeb.Scope.opts(socket)
             ),
           callback =
             AlgoieWeb.PublicURL.store(
               socket.assigns.store.slug,
               "/dashboard/social/callback?platform=#{platform}"
             ),
           {:ok, url} <-
             SocialPublishing.connect_url(profile.provider_profile_id, platform, callback) do
        {:noreply, redirect(socket, external: url)}
      else
        {:error, :provider_not_configured} ->
          {:noreply, put_flash(socket, :error, "Social publishing is not configured yet")}

        {:error, {:provider_error, 402, _details}} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "The social account connection limit has been reached. Contact the platform administrator."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not start this connection")}
      end
    end
  end

  def handle_event("connect", _, socket),
    do: {:noreply, put_flash(socket, :error, "Unsupported platform")}

  def handle_event(
        "select-facebook-page",
        %{"page-id" => page_id},
        %{assigns: %{facebook_connection: connection}} = socket
      )
      when is_map(connection) do
    if Enum.any?(socket.assigns.facebook_pages, &(&1["id"] == page_id)) do
      redirect_url = AlgoieWeb.PublicURL.store(socket.assigns.store.slug, "/dashboard/social")

      case SocialPublishing.select_facebook_page(
             connection.profile_id,
             page_id,
             connection.temp_token,
             connection.user_profile,
             redirect_url
           ) do
        {:ok, _result} ->
          case SocialPublishing.sync_accounts(
                 socket.assigns.social_profile,
                 AlgoieWeb.Scope.opts(socket)
               ) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, "Facebook Page connected")
               |> push_navigate(to: ~p"/dashboard/social")}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(
                 :error,
                 "The Page connected, but account sync failed. Please refresh."
               )
               |> push_navigate(to: ~p"/dashboard/social")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not connect that Facebook Page")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please choose a valid Facebook Page")}
    end
  end

  def handle_event("select-facebook-page", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Your Facebook connection has expired")}

  def handle_event("delete-account", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.social_accounts, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Connected account was not found")}

      account ->
        case SocialPublishing.delete_account(account, AlgoieWeb.Scope.opts(socket)) do
          :ok ->
            {:noreply,
             socket
             |> load_social()
             |> put_flash(:info, "#{platform_name(account.platform)} account removed")}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Could not remove the account from the social provider. Please retry."
             )}
        end
    end
  end

  defp load_social(socket) do
    case SocialPublishing.profile_for_store(socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, nil} ->
        assign_social(socket, nil, [])

      {:ok, profile} ->
        accounts =
          SocialAccount
          |> Ash.Query.filter(social_profile_id == ^profile.id)
          |> Ash.read!(AlgoieWeb.Scope.opts(socket))
          |> Enum.filter(&(Atom.to_string(&1.platform) in @account_platforms))

        assign_social(socket, profile, accounts)

      _ ->
        assign_social(socket, nil, [])
    end
  end

  defp assign_social(socket, profile, accounts) do
    connected_platforms = Enum.map(accounts, &Atom.to_string(&1.platform))

    assign(socket,
      social_profile: profile,
      social_accounts: accounts,
      available_platforms: @oauth_platforms -- connected_platforms
    )
  end

  defp connected_platform?(accounts, platform) do
    Enum.any?(accounts, &(Atom.to_string(&1.platform) == platform))
  end

  defp platform_name(platform) when is_atom(platform),
    do: platform |> Atom.to_string() |> platform_name()

  defp platform_name(platform) when is_binary(platform), do: String.capitalize(platform)

  defp decode_user_profile(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, profile} when is_map(profile) -> {:ok, profile}
      _ -> decode_uri_user_profile(value)
    end
  end

  defp decode_user_profile(_value), do: {:error, :invalid_user_profile}

  defp decode_uri_user_profile(value) do
    value
    |> URI.decode()
    |> Jason.decode()
    |> case do
      {:ok, profile} when is_map(profile) -> {:ok, profile}
      _ -> {:error, :invalid_user_profile}
    end
  rescue
    ArgumentError -> {:error, :invalid_user_profile}
  end
end
