defmodule Algoie.ChannelStudio.Publishing.Facebook do
  @moduledoc "Facebook post validation and payload construction."

  alias Algoie.ChannelStudio.Publishing.Validation, as: V

  @types ~w(feed story reel draft)

  def validate(post) do
    content = post["content"] || ""
    type = post["content_type"] || "feed"
    media = post["media_items"] || []
    images = V.images(media)
    videos = V.videos(media)

    []
    |> V.maybe(type not in @types, :content_type, "Choose a supported Facebook content type")
    |> V.maybe(
      String.length(content) > 63_206,
      :content,
      "Facebook text cannot exceed 63,206 characters"
    )
    |> V.maybe(
      type == "story" and media == [],
      :media,
      "Facebook Stories require one image or video"
    )
    |> V.maybe(
      type == "story" and length(media) > 1,
      :media,
      "Facebook Stories support one media item"
    )
    |> V.maybe(type == "reel" and length(videos) != 1, :media, "Facebook Reels require one video")
    |> V.maybe(type == "reel" and images != [], :media, "Facebook Reels do not support images")
    |> V.maybe(length(images) > 10, :media, "Facebook supports at most 10 images")
    |> V.maybe(length(videos) > 1, :media, "Facebook supports one video")
    |> V.maybe(images != [] and videos != [], :media, "Facebook cannot mix images and video")
    |> V.maybe(content == "" and media == [], :content, "Add text or media")
    |> validate_media(media)
    |> validate_carousel(post, images, videos)
    |> V.finish()
  end

  def platform(account_id, post) do
    data =
      %{}
      |> put_content_type(post["content_type"])
      |> put_present("title", post["title"])
      |> put_present("firstComment", post["first_comment"])
      |> put_countries(post["countries"])

    %{"platform" => "facebook", "accountId" => account_id, "platformSpecificData" => data}
  end

  def settings(post) do
    %{}
    |> put_truthy("draft", post["content_type"] == "draft")
    |> put_present("carouselLink", post["carousel_link"])
    |> put_carousel_cards(post)
  end

  defp validate_media(errors, media) do
    Enum.reduce(media, errors, fn item, acc ->
      type = V.media_type(item)
      size = V.media_size(item)

      acc
      |> V.maybe(
        type == "image" and is_number(size) and size > 4_000_000,
        :media,
        "Facebook images must be 4 MB or smaller"
      )
      |> V.maybe(
        type == "video" and is_number(size) and size > 4_000_000_000,
        :media,
        "Facebook videos must be 4 GB or smaller"
      )
    end)
  end

  defp validate_carousel(errors, post, images, videos) do
    carousel? = post["carousel"] in [true, "true", "on"]

    errors
    |> V.maybe(
      carousel? and videos != [],
      :carousel,
      "Facebook link carousels support images only"
    )
    |> V.maybe(
      carousel? and length(images) not in 2..5,
      :carousel,
      "Facebook link carousels require 2–5 images"
    )
  end

  defp put_content_type(data, type) when type in ["story", "reel"],
    do: Map.put(data, "contentType", type)

  defp put_content_type(data, _type), do: data

  defp put_countries(data, countries) when is_list(countries) and countries != [] do
    Map.put(data, "geoRestriction", %{"countries" => Enum.take(countries, 25)})
  end

  defp put_countries(data, _countries), do: data

  defp put_carousel_cards(data, %{"carousel" => carousel, "carousel_cards" => cards})
       when carousel in [true, "true", "on"] and is_list(cards) do
    Map.put(data, "carouselCards", cards)
  end

  defp put_carousel_cards(data, _post), do: data
  defp put_truthy(data, _key, false), do: data
  defp put_truthy(data, key, true), do: Map.put(data, key, true)
  defp put_present(data, _key, value) when value in [nil, ""], do: data
  defp put_present(data, key, value), do: Map.put(data, key, value)
end
