defmodule Algoie.ChannelStudio.ContractsTest do
  use ExUnit.Case, async: false

  alias Algoie.ChannelStudio.{Inbox, WhatsApp}
  alias Algoie.ChannelStudio.Publishing.Tiktok

  setup do
    previous_provider = Application.get_env(:algoie, :channel_studio_provider)
    previous_pid = Application.get_env(:algoie, :channel_studio_test_pid)

    Application.put_env(:algoie, :channel_studio_provider, Algoie.ChannelStudioTestProvider)
    Application.put_env(:algoie, :channel_studio_test_pid, self())

    on_exit(fn ->
      restore_env(:channel_studio_provider, previous_provider)
      restore_env(:channel_studio_test_pid, previous_pid)
    end)

    :ok
  end

  test "marks a conversation read with the required account id" do
    assert {:ok, _response} = Inbox.mark_read("thread/1", "wa-1")

    assert_receive {:channel_studio_request, :post, "/inbox/conversations/thread%2F1/read",
                    %{"accountId" => "wa-1"}, [], [{"x-request-id", request_id}]}

    assert {:ok, _uuid} = Ecto.UUID.cast(request_id)
  end

  test "adds raw phone recipients using the documented phones field" do
    phones = ["+15551234567", "+447700900123"]
    assert {:ok, _response} = WhatsApp.add_recipients("broadcast-1", phones)

    assert_receive {:channel_studio_request, :post, "/broadcasts/broadcast-1/recipients",
                    %{"phones" => ^phones}, [], _headers}
  end

  test "fetches creator-specific TikTok publishing options" do
    assert {:ok, _response} = Tiktok.creator_info("tt/account", "video")

    assert_receive {:channel_studio_request, :get, "/accounts/tt%2Faccount/tiktok/creator-info",
                    nil, [mediaType: "video"], []}
  end

  test "TikTok settings include both required consent confirmations" do
    settings = Tiktok.settings(%{"privacy_level" => "PUBLIC_TO_EVERYONE", "consent" => "true"})

    assert settings["privacyLevel"] == "PUBLIC_TO_EVERYONE"
    assert settings["contentPreviewConfirmed"]
    assert settings["expressConsentGiven"]
  end

  defp restore_env(key, nil), do: Application.delete_env(:algoie, key)
  defp restore_env(key, value), do: Application.put_env(:algoie, key, value)
end
