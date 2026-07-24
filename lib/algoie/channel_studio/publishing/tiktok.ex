defmodule Algoie.ChannelStudio.Publishing.Tiktok do
  @moduledoc "TikTok post validation and top-level settings construction."

  alias Algoie.ChannelStudio.Publishing.Validation, as: V
  alias Algoie.ChannelStudio

  def creator_info(account_id, media_type) when media_type in ["image", "video"] do
    ChannelStudio.get(
      "/accounts/#{ChannelStudio.segment(account_id)}/tiktok/creator-info",
      mediaType: media_type
    )
  end

  def validate(post) do
    media = post["media_items"] || []
    images = V.images(media)
    videos = V.videos(media)
    description = post["description"] || ""
    title = post["content"] || ""

    []
    |> V.maybe(media == [], :media, "TikTok posts require media")
    |> V.maybe(images != [] and videos != [], :media, "TikTok cannot mix photos and video")
    |> V.maybe(length(videos) > 1, :media, "TikTok supports one video")
    |> V.maybe(length(images) > 35, :media, "TikTok photo carousels support at most 35 images")
    |> V.maybe(
      videos != [] and String.length(title) > 2_200,
      :content,
      "TikTok video captions cannot exceed 2,200 characters"
    )
    |> V.maybe(
      images != [] and String.length(title) > 90,
      :content,
      "TikTok photo titles cannot exceed 90 characters"
    )
    |> V.maybe(
      images != [] and String.length(description) > 4_000,
      :description,
      "TikTok photo descriptions cannot exceed 4,000 characters"
    )
    |> V.maybe(
      blank?(post["privacy_level"]),
      :privacy_level,
      "Choose one of this creator's available privacy levels"
    )
    |> V.maybe(not truthy?(post["consent"]), :consent, "TikTok publishing consent is required")
    |> validate_video(videos)
    |> V.finish()
  end

  def platform(account_id, post) do
    %{
      "platform" => "tiktok",
      "accountId" => account_id,
      "platformSpecificData" => %{"draft" => truthy?(post["draft"])}
    }
  end

  def settings(post) do
    %{}
    |> put_present("privacyLevel", post["privacy_level"])
    |> put_present("description", post["description"])
    |> put_present("autoAddMusic", post["auto_add_music"])
    |> put_present("disableComment", post["disable_comment"])
    |> put_present("disableDuet", post["disable_duet"])
    |> put_present("disableStitch", post["disable_stitch"])
    |> put_present("brandContentToggle", post["brand_content"])
    |> put_present("brandOrganicToggle", post["brand_organic"])
    |> put_present("isAigc", post["is_ai_generated"])
    |> Map.put("contentPreviewConfirmed", truthy?(post["consent"]))
    |> Map.put("expressConsentGiven", truthy?(post["consent"]))
  end

  defp validate_video(errors, [video]) do
    duration = V.media_duration(video)
    size = V.media_size(video)

    errors
    |> V.maybe(
      is_number(duration) and (duration < 3 or duration > 600),
      :media,
      "TikTok videos must be 3 seconds–10 minutes"
    )
    |> V.maybe(
      is_number(size) and size > 4_000_000_000,
      :media,
      "TikTok videos must be 4 GB or smaller"
    )
  end

  defp validate_video(errors, _videos), do: errors
  defp blank?(value), do: value in [nil, ""]
  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp put_present(data, _key, value) when value in [nil, "", []], do: data
  defp put_present(data, key, value), do: Map.put(data, key, value)
end
