defmodule Algoie.ChannelStudio.Publishing.Instagram do
  @moduledoc "Instagram post validation and payload construction."

  alias Algoie.ChannelStudio.Publishing.Validation, as: V

  @types ~w(feed story reels)

  def validate(post) do
    content = post["content"] || ""
    type = post["content_type"] || "feed"
    media = post["media_items"] || []
    videos = V.videos(media)

    []
    |> V.maybe(type not in @types, :content_type, "Choose a supported Instagram content type")
    |> V.maybe(
      String.length(content) > 2_200,
      :content,
      "Instagram captions cannot exceed 2,200 characters"
    )
    |> V.maybe(media == [], :media, "Instagram posts require media")
    |> V.maybe(
      type in ["story", "reels"] and length(media) != 1,
      :media,
      "Instagram Stories and Reels require one media item"
    )
    |> V.maybe(
      type == "reels" and length(videos) != 1,
      :media,
      "Instagram Reels require one video"
    )
    |> V.maybe(
      type == "feed" and length(media) > 10,
      :media,
      "Instagram carousels support at most 10 items"
    )
    |> V.maybe(
      length(List.wrap(post["collaborators"])) > 3,
      :collaborators,
      "Instagram supports at most three collaborators"
    )
    |> validate_media(type, media)
    |> V.finish()
  end

  def platform(account_id, post) do
    type = post["content_type"] || "feed"

    data =
      %{}
      |> put_content_type(type)
      |> put_present("firstComment", post["first_comment"])
      |> put_present("shareToFeed", post["share_to_feed"])
      |> put_present("collaborators", post["collaborators"])
      |> put_present("userTags", post["user_tags"])
      |> put_present("isAiGenerated", post["is_ai_generated"])
      |> put_present("thumbOffset", post["thumb_offset"])
      |> put_present("instagramThumbnail", post["instagram_thumbnail"])
      |> put_present("audioName", post["audio_name"])

    %{"platform" => "instagram", "accountId" => account_id, "platformSpecificData" => data}
  end

  defp validate_media(errors, type, media) do
    Enum.reduce(media, errors, fn item, acc ->
      media_type = V.media_type(item)
      size = V.media_size(item)
      duration = V.media_duration(item)

      acc
      |> V.maybe(
        type == "story" and media_type == "image" and is_number(size) and size > 8_000_000,
        :media,
        "Instagram Story images must be 8 MB or smaller"
      )
      |> V.maybe(
        type == "story" and media_type == "video" and is_number(size) and size > 100_000_000,
        :media,
        "Instagram Story videos must be 100 MB or smaller"
      )
      |> V.maybe(
        type == "story" and media_type == "video" and is_number(duration) and duration > 60,
        :media,
        "Instagram Story videos cannot exceed 60 seconds"
      )
      |> V.maybe(
        type == "reels" and is_number(size) and size > 300_000_000,
        :media,
        "Instagram Reels must be 300 MB or smaller"
      )
      |> V.maybe(
        type == "reels" and is_number(duration) and (duration < 3 or duration > 90),
        :media,
        "Instagram Reels must be 3–90 seconds"
      )
    end)
  end

  defp put_content_type(data, type) when type in ["story", "reels"],
    do: Map.put(data, "contentType", type)

  defp put_content_type(data, _type), do: data
  defp put_present(data, _key, value) when value in [nil, "", []], do: data
  defp put_present(data, key, value), do: Map.put(data, key, value)
end
