defmodule AlgoieWeb.FacebookStudio do
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
      account = facebook_account(profile, opts)

      socket
      |> assign(:store, store)
      |> assign(:social_profile, profile)
      |> assign(:facebook_account, account)
    else
      _ ->
        socket
        |> assign(:store, nil)
        |> assign(:social_profile, nil)
        |> assign(:facebook_account, nil)
    end
  end

  def subscribe(%{assigns: %{facebook_account: %{provider_account_id: id}}} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(Algoie.PubSub, "zernio:#{id}")
    end

    socket
  end

  def subscribe(socket), do: socket

  def manage?(socket) do
    permissions = socket.assigns.store_permissions
    "social.manage" in permissions or "settings.manage" in permissions
  end

  def list(response, key), do: Map.get(response, key, [])

  def pagination(response) do
    Map.get(response, "pagination", %{"page" => 1, "pages" => 1, "total" => 0})
  end

  def provider_error(%{"error" => value}) when is_binary(value), do: value
  def provider_error(%{"message" => value}) when is_binary(value), do: value
  def provider_error(_), do: "Facebook could not complete that request."

  def locked_error?({:provider_error, status, _body}) when status in [402, 403], do: true
  def locked_error?(_reason), do: false

  defp facebook_account(nil, _opts), do: nil

  defp facebook_account(profile, opts) do
    SocialAccount
    |> Ash.Query.filter(social_profile_id == ^profile.id and platform == :facebook)
    |> Ash.read_one(opts)
    |> case do
      {:ok, account} -> account
      _ -> nil
    end
  end
end
