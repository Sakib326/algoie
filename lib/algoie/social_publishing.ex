defmodule Algoie.SocialPublishing do
  @moduledoc "Provider-independent social publishing entry point."

  alias Algoie.SocialPublishingSetting
  alias Algoie.SocialPublishing.{SocialAccount, SocialProfile}

  require Ash.Query

  @adapters %{"zernio" => Algoie.SocialPublishing.Adapters.Zernio}

  def adapter do
    settings = SocialPublishingSetting.get()
    Map.get(@adapters, settings.active_adapter, Algoie.SocialPublishing.Adapters.Zernio)
  end

  def create_profile(store), do: adapter().create_profile(store)

  def connect_url(profile_id, platform, redirect_url),
    do: adapter().connect_url(profile_id, platform, redirect_url)

  def list_accounts(profile_id), do: adapter().list_accounts(profile_id)

  def get_or_create_profile(store, opts) do
    case profile_for_store(store.id, opts) do
      {:ok, %SocialProfile{} = profile} -> {:ok, profile}
      {:ok, nil} -> create_store_profile(store, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def profile_for_store(store_id, opts) do
    SocialProfile
    |> Ash.Query.filter(store_id == ^store_id)
    |> Ash.read_one(opts)
  end

  def sync_accounts(%SocialProfile{} = profile, opts) do
    with {:ok, accounts} <- list_accounts(profile.provider_profile_id) do
      Enum.reduce_while(accounts, {:ok, []}, fn account, {:ok, synced} ->
        case upsert_account(profile, account, opts) do
          {:ok, record} -> {:cont, {:ok, [record | synced]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp create_store_profile(store, opts) do
    with {:ok, provider_id} <- create_profile(store) do
      SocialProfile
      |> Ash.Changeset.for_create(:create, %{
        store_id: store.id,
        name: store.name,
        provider_profile_id: provider_id
      })
      |> Ash.create(opts)
    end
  end

  defp upsert_account(profile, %{"_id" => provider_id, "platform" => platform} = raw, opts) do
    with {:ok, platform} <- platform_atom(platform),
         {:ok, existing} <- account_by_provider_id(provider_id, opts) do
      attrs = %{
        social_profile_id: profile.id,
        provider_account_id: provider_id,
        platform: platform,
        status: :connected,
        metadata: raw
      }

      case existing do
        nil -> Ash.create(SocialAccount, attrs, opts)
        account -> Ash.update(account, Map.drop(attrs, [:provider_account_id]), opts)
      end
    end
  end

  defp upsert_account(_profile, _raw, _opts), do: {:error, :invalid_provider_account}

  defp account_by_provider_id(provider_id, opts) do
    SocialAccount
    |> Ash.Query.filter(provider_account_id == ^provider_id)
    |> Ash.read_one(opts)
  end

  defp platform_atom(platform) do
    platforms = Algoie.SocialPublishing.SocialAccount.platforms()

    if platform in platforms,
      do: {:ok, String.to_existing_atom(platform)},
      else: {:error, :unsupported_platform}
  end
end
