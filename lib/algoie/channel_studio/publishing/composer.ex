defmodule Algoie.ChannelStudio.Publishing.Composer do
  @moduledoc "Builds a single post request while preserving platform-specific contracts."

  alias Algoie.ChannelStudio.Publishing.{Facebook, Instagram, Tiktok}

  @builders %{
    "facebook" => Facebook,
    "instagram" => Instagram,
    "tiktok" => Tiktok
  }

  def build(post, targets) when is_map(post) and is_list(targets) do
    with :ok <- validate_targets(post, targets),
         :ok <- validate_each(post, targets) do
      platforms = Enum.map(targets, &platform_payload(&1, post))

      payload =
        %{
          "content" => post["content"] || "",
          "mediaItems" => post["media_items"] || [],
          "platforms" => platforms
        }
        |> put_delivery(post)
        |> put_settings("facebookSettings", Facebook.settings(post), targets, "facebook")
        |> put_settings("tiktokSettings", Tiktok.settings(post), targets, "tiktok")

      {:ok, payload}
    end
  end

  defp validate_targets(%{"delivery" => "draft"}, []), do: :ok

  defp validate_targets(_post, []),
    do: {:error, %{targets: ["Select at least one publishing destination"]}}

  defp validate_targets(_post, targets) do
    if Enum.all?(
         targets,
         &(is_map(&1) and Map.has_key?(@builders, &1["platform"]) and is_binary(&1["account_id"]))
       ) do
      :ok
    else
      {:error, %{targets: ["One or more publishing destinations are invalid"]}}
    end
  end

  defp validate_each(post, targets) do
    errors =
      Enum.reduce(targets, %{}, fn target, acc ->
        platform = target["platform"]

        case @builders[platform].validate(platform_post(post, platform)) do
          :ok -> acc
          {:error, platform_errors} -> Map.put(acc, platform, platform_errors)
        end
      end)

    if errors == %{}, do: :ok, else: {:error, errors}
  end

  defp platform_payload(target, post) do
    platform = target["platform"]
    @builders[platform].platform(target["account_id"], platform_post(post, platform))
  end

  defp platform_post(post, platform) do
    overrides = get_in(post, ["platform_overrides", platform]) || %{}
    Map.merge(post, overrides)
  end

  defp put_delivery(payload, %{"delivery" => "now"}), do: Map.put(payload, "publishNow", true)

  defp put_delivery(payload, %{"delivery" => "schedule", "scheduled_for" => scheduled_for})
       when is_binary(scheduled_for) and scheduled_for != "" do
    Map.put(payload, "scheduledFor", scheduled_for)
  end

  defp put_delivery(payload, _post), do: Map.put(payload, "isDraft", true)

  defp put_settings(payload, _key, settings, _targets, _platform) when settings == %{},
    do: payload

  defp put_settings(payload, key, settings, targets, platform) do
    if Enum.any?(targets, &(&1["platform"] == platform)),
      do: Map.put(payload, key, settings),
      else: payload
  end
end
