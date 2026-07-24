defmodule Algoie.ChannelStudio.Publishing.ComposerTest do
  use ExUnit.Case, async: true

  alias Algoie.ChannelStudio.Publishing.Composer

  test "builds separate Facebook and Instagram platform data" do
    post = %{
      "content" => "New product",
      "content_type" => "feed",
      "media_items" => [%{"type" => "image", "url" => "https://cdn.example/item.jpg"}],
      "delivery" => "now"
    }

    targets = [
      %{"platform" => "facebook", "account_id" => "fb-1"},
      %{"platform" => "instagram", "account_id" => "ig-1"}
    ]

    assert {:ok, payload} = Composer.build(post, targets)
    assert payload["publishNow"]
    assert Enum.map(payload["platforms"], & &1["platform"]) == ["facebook", "instagram"]
  end

  test "does not allow a text-only post when Instagram is selected" do
    post = %{
      "content" => "Text only",
      "content_type" => "feed",
      "media_items" => [],
      "delivery" => "now"
    }

    assert {:error, %{"instagram" => errors}} =
             Composer.build(post, [%{"platform" => "instagram", "account_id" => "ig-1"}])

    assert {:media, "Instagram posts require media"} in errors
  end

  test "uses Instagram reels and Facebook reel independently through overrides" do
    post = %{
      "content" => "Watch this",
      "content_type" => "reel",
      "media_items" => [
        %{"type" => "video", "url" => "https://cdn.example/reel.mp4", "duration" => 30}
      ],
      "delivery" => "now",
      "platform_overrides" => %{"instagram" => %{"content_type" => "reels"}}
    }

    targets = [
      %{"platform" => "facebook", "account_id" => "fb-1"},
      %{"platform" => "instagram", "account_id" => "ig-1"}
    ]

    assert {:ok, payload} = Composer.build(post, targets)
    [facebook, instagram] = payload["platforms"]
    assert facebook["platformSpecificData"]["contentType"] == "reel"
    assert instagram["platformSpecificData"]["contentType"] == "reels"
  end

  test "requires TikTok privacy and consent" do
    post = %{
      "content" => "Video",
      "content_type" => "feed",
      "media_items" => [
        %{"type" => "video", "url" => "https://cdn.example/video.mp4", "duration" => 15}
      ],
      "delivery" => "now"
    }

    assert {:error, %{"tiktok" => errors}} =
             Composer.build(post, [%{"platform" => "tiktok", "account_id" => "tt-1"}])

    assert {:privacy_level, _} = Enum.find(errors, &(elem(&1, 0) == :privacy_level))
    assert {:consent, _} = Enum.find(errors, &(elem(&1, 0) == :consent))
  end

  test "keeps TikTok settings at the request root" do
    post = %{
      "content" => "Video",
      "content_type" => "feed",
      "media_items" => [
        %{"type" => "video", "url" => "https://cdn.example/video.mp4", "duration" => 15}
      ],
      "privacy_level" => "PUBLIC_TO_EVERYONE",
      "consent" => true,
      "delivery" => "now"
    }

    assert {:ok, payload} =
             Composer.build(post, [%{"platform" => "tiktok", "account_id" => "tt-1"}])

    assert payload["tiktokSettings"]["privacyLevel"] == "PUBLIC_TO_EVERYONE"
  end

  test "allows a destination-free studio draft" do
    post = %{
      "content" => "Finish this later",
      "content_type" => "feed",
      "media_items" => [],
      "delivery" => "draft"
    }

    assert {:ok, payload} = Composer.build(post, [])
    assert payload["isDraft"]
    assert payload["platforms"] == []
  end
end
