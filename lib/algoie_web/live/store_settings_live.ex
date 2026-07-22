defmodule AlgoieWeb.StoreSettingsLive do
  use AlgoieWeb, :live_view

  alias Algoie.Stores.Store
  alias Algoie.SocialPublishing

  @oauth_platforms ~w(twitter instagram facebook linkedin tiktok youtube pinterest reddit threads googlebusiness snapchat whatsapp discord)

  @impl true
  def mount(_params, _session, socket) do
    case Ash.get(Store, socket.assigns.store_id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, store} ->
        form = AshPhoenix.Form.for_update(store, :update, domain: Algoie.Stores, as: "store")

        {:ok,
         socket
         |> assign(:active, :settings)
         |> assign(:page_title, "Store settings")
         |> assign(:store, store)
         |> assign(:form, to_form(form))
         |> assign(:social_platforms, @oauth_platforms)
         |> load_social()}

      _ ->
        {:ok,
         socket
         |> assign(:active, :settings)
         |> assign(:page_title, "Store settings")
         |> assign(:store, nil)
         |> assign(:form, nil)
         |> assign(:social_platforms, @oauth_platforms)
         |> assign(:social_profile, nil)
         |> assign(:social_accounts, [])}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :social_callback}} = socket) do
    case socket.assigns.social_profile do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Social profile was not found")
         |> push_navigate(to: "/dashboard/settings")}

      profile ->
        case SocialPublishing.sync_accounts(profile, AlgoieWeb.Scope.opts(socket)) do
          {:ok, _accounts} ->
            {:noreply,
             socket
             |> load_social()
             |> put_flash(:info, "Social account connected")
             |> push_navigate(to: "/dashboard/settings")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "The provider connection could not be synchronized")
             |> push_navigate(to: "/dashboard/settings")}
        end
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"store" => params}, socket) do
    params = Map.put(params, "currency", "BDT")
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"store" => params}, socket) do
    params = Map.put(params, "currency", "BDT")

    case AshPhoenix.Form.submit(socket.assigns.form,
           params: params,
           action_opts: AlgoieWeb.Scope.opts(socket)
         ) do
      {:ok, store} ->
        form = AshPhoenix.Form.for_update(store, :update, domain: Algoie.Stores, as: "store")

        {:noreply,
         socket
         |> assign(:store, store)
         |> assign(:store_name, store.name)
         |> assign(:form, to_form(form))
         |> put_flash(:info, "Store settings saved")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Please correct the highlighted fields.")}
    end
  end

  def handle_event("connect-social", %{"platform" => platform}, socket)
      when platform in @oauth_platforms do
    with {:ok, profile} <-
           SocialPublishing.get_or_create_profile(
             socket.assigns.store,
             AlgoieWeb.Scope.opts(socket)
           ),
         redirect_url =
           AlgoieWeb.PublicURL.store(
             socket.assigns.store.slug,
             "/dashboard/settings/social/callback?platform=#{platform}"
           ),
         {:ok, url} <-
           SocialPublishing.connect_url(profile.provider_profile_id, platform, redirect_url) do
      {:noreply, redirect(socket, external: url)}
    else
      {:error, :provider_not_configured} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Social publishing is not configured by the platform administrator"
         )}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not start the social account connection. Please retry.")}
    end
  end

  def handle_event("connect-social", _params, socket),
    do: {:noreply, put_flash(socket, :error, "That social platform is not supported")}

  defp load_social(%{assigns: %{store: %Store{} = store}} = socket) do
    case SocialPublishing.profile_for_store(store.id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, nil} ->
        assign(socket, social_profile: nil, social_accounts: [])

      {:ok, profile} ->
        accounts = Ash.load!(profile, :accounts, AlgoieWeb.Scope.opts(socket)).accounts
        assign(socket, social_profile: profile, social_accounts: accounts)

      _ ->
        assign(socket, social_profile: nil, social_accounts: [])
    end
  end

  defp load_social(socket), do: socket
end
