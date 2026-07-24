defmodule Algoie.ChannelStudio.Provider do
  @moduledoc """
  Transport boundary for Channel Studio providers.

  Domain modules own the product vocabulary and payload validation. Providers
  only execute normalized HTTP-style requests, which keeps Zernio replaceable.
  """

  @type method :: :get | :post | :put | :patch | :delete
  @type result :: {:ok, map() | list()} | {:error, term()}

  @callback request(method(), String.t(), map() | nil, keyword(), [{String.t(), String.t()}]) ::
              result()
end
