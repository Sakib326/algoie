defmodule Algoie.EmailDelivery do
  @moduledoc "Resolves store-specific email delivery with platform fallback."

  alias Algoie.{PlatformEmailSettings, StoreEmailSettings}

  def resolve(%{tenant: tenant, store_id: store_id}) when is_binary(tenant) do
    settings = StoreEmailSettings.get(tenant, store_id)

    if StoreEmailSettings.configured?(settings),
      do: StoreEmailSettings.delivery_config(settings),
      else: platform()
  rescue
    _error -> platform()
  end

  def resolve(_context), do: platform()
  defp platform, do: PlatformEmailSettings.get() |> PlatformEmailSettings.delivery_config()
end
