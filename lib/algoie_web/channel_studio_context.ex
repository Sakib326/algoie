defmodule AlgoieWeb.ChannelStudioContext do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Algoie.SocialPublishing
  alias Algoie.SocialPublishing.SocialAccount
  alias Algoie.Stores.Store

  require Ash.Query

  def load(socket) do
    opts = AlgoieWeb.Scope.opts(socket)

    with {:ok, store} <- Ash.get(Store, socket.assigns.store_id, opts),
         {:ok, profile} <- SocialPublishing.profile_for_store(store.id, opts) do
      accounts = accounts(profile, opts)

      socket
      |> assign(:store, store)
      |> assign(:social_profile, profile)
      |> assign(:channel_accounts, accounts)
    else
      _ ->
        socket
        |> assign(:store, nil)
        |> assign(:social_profile, nil)
        |> assign(:channel_accounts, [])
    end
  end

  def subscribe(socket) do
    if Phoenix.LiveView.connected?(socket) do
      Enum.each(socket.assigns.channel_accounts, fn account ->
        Phoenix.PubSub.subscribe(Algoie.PubSub, "zernio:#{account.provider_account_id}")
      end)
    end

    socket
  end

  def account(socket, platform) when is_binary(platform) do
    Enum.find(socket.assigns.channel_accounts, &(Atom.to_string(&1.platform) == platform))
  end

  def account_id(socket, platform) do
    case account(socket, platform) do
      nil -> nil
      account -> account.provider_account_id
    end
  end

  def connected?(account), do: account && account.status == :connected

  def manage?(socket) do
    permissions = socket.assigns.store_permissions
    "social.manage" in permissions or "settings.manage" in permissions
  end

  defp accounts(nil, _opts), do: []

  defp accounts(profile, opts) do
    SocialAccount
    |> Ash.Query.filter(social_profile_id == ^profile.id)
    |> Ash.Query.sort(platform: :asc)
    |> Ash.read!(opts)
  end
end
