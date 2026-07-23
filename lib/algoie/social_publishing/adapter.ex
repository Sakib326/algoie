defmodule Algoie.SocialPublishing.Adapter do
  @moduledoc "Provider-neutral contract for social publishing integrations."

  @callback create_profile(store :: struct()) ::
              {:ok, String.t()} | {:error, term()}
  @callback connect_url(
              profile_id :: String.t(),
              platform :: String.t(),
              redirect_url :: String.t()
            ) ::
              {:ok, String.t()} | {:error, term()}
  @callback list_accounts(profile_id :: String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback delete_account(account_id :: String.t()) :: :ok | {:error, term()}
  @callback create_post(payload :: map()) :: {:ok, map()} | {:error, term()}
  @callback list_facebook_pages(profile_id :: String.t(), temp_token :: String.t()) ::
              {:ok, [map()]} | {:error, term()}
  @callback select_facebook_page(
              profile_id :: String.t(),
              page_id :: String.t(),
              temp_token :: String.t(),
              user_profile :: map(),
              redirect_url :: String.t()
            ) :: {:ok, map()} | {:error, term()}
end
