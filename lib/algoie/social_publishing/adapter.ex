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
end
