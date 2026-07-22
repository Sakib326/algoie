defmodule AlgoieWeb.SocialPublishingLive do
  use AlgoieWeb, :live_view
  alias Algoie.SocialPublishing
  alias Algoie.SocialPublishing.SocialAccount
  require Ash.Query
  alias Algoie.Stores.Store

  @platforms ~w(twitter instagram facebook linkedin tiktok youtube pinterest reddit threads googlebusiness snapchat whatsapp discord)

  def mount(_params, _session, socket) do
    case Ash.get(Store, socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, store} ->
        {:ok,
         socket
         |> assign(:store, store)
         |> assign(:page_title, "Social publishing")
         |> assign(:platforms, @platforms)
         |> load_social()}

      _ ->
        {:ok, redirect(socket, to: "/dashboard")}
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

  def handle_event("connect", %{"platform" => platform}, socket) when platform in @platforms do
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
           "Zernio has reached its free account limit. Add a payment method in Zernio billing to connect another account."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start this connection")}
    end
  end

  def handle_event("connect", _, socket),
    do: {:noreply, put_flash(socket, :error, "Unsupported platform")}

  defp load_social(socket) do
    case SocialPublishing.profile_for_store(socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, nil} ->
        assign(socket, social_profile: nil, social_accounts: [])

      {:ok, profile} ->
        accounts =
          SocialAccount
          |> Ash.Query.filter(social_profile_id == ^profile.id)
          |> Ash.read!(AlgoieWeb.Scope.opts(socket))

        assign(socket,
          social_profile: profile,
          social_accounts: accounts
        )

      _ ->
        assign(socket, social_profile: nil, social_accounts: [])
    end
  end
end
