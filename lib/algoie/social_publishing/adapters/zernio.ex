defmodule Algoie.SocialPublishing.Adapters.Zernio do
  @behaviour Algoie.SocialPublishing.Adapter

  alias Algoie.SocialPublishingSetting

  @base_url "https://zernio.com/api/v1"
  @oauth_platforms ~w(twitter instagram facebook linkedin tiktok youtube pinterest reddit threads googlebusiness snapchat whatsapp discord)

  def supported_platforms, do: @oauth_platforms

  @impl true
  def create_profile(store) do
    attrs = %{name: store.name, description: "Algoie store #{store.slug}"}

    case create_profile_request(attrs) do
      {:error, {:provider_error, 409, %{"code" => "profile_name_conflict"}}} ->
        suffix = store.id |> to_string() |> String.slice(0, 8)
        create_profile_request(%{attrs | name: "#{store.name} · #{suffix}"})

      result ->
        result
    end
  end

  defp create_profile_request(attrs) do
    with {:ok, response} <- request(:post, "/profiles", attrs),
         id when is_binary(id) <- get_in(response, ["profile", "_id"]) do
      {:ok, id}
    else
      nil -> {:error, :invalid_provider_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def connect_url(profile_id, platform, redirect_url)
      when platform in @oauth_platforms do
    with {:ok, %{"authUrl" => url}} <-
           request(:get, "/connect/#{platform}", nil,
             profileId: profile_id,
             redirect_url: redirect_url
           ) do
      {:ok, url}
    else
      {:ok, _} -> {:error, :invalid_provider_response}
      {:error, reason} -> {:error, reason}
    end
  end

  def connect_url(_profile_id, platform, _redirect_url) when platform in ~w(bluesky telegram),
    do: {:error, {:unsupported_day_one_flow, platform}}

  def connect_url(_profile_id, _platform, _redirect_url), do: {:error, :unsupported_platform}

  @impl true
  def list_accounts(profile_id) do
    case request(:get, "/accounts", nil, profileId: profile_id) do
      {:ok, %{"accounts" => accounts}} when is_list(accounts) -> {:ok, accounts}
      {:ok, _} -> {:error, :invalid_provider_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(method, path, body, params \\ []) do
    settings = SocialPublishingSetting.get()

    with api_key when is_binary(api_key) <- SocialPublishingSetting.api_key(settings),
         false <- api_key == "" do
      opts = [
        headers: [{"authorization", "Bearer #{api_key}"}],
        params: params,
        receive_timeout: 15_000
      ]

      opts = if body, do: Keyword.put(opts, :json, body), else: opts

      case Req.request(Keyword.merge([method: method, url: @base_url <> path], opts)) do
        {:ok, %{status: status, body: response}} when status in 200..299 -> {:ok, response}
        {:ok, %{status: status, body: response}} -> {:error, {:provider_error, status, response}}
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:error, :provider_not_configured}
      true -> {:error, :provider_not_configured}
    end
  end
end
