defmodule Algoie.ChannelStudio.Publishing.Validation do
  @moduledoc false

  def error(errors, field, message), do: [{field, message} | errors]
  def maybe(errors, true, field, message), do: error(errors, field, message)
  def maybe(errors, false, _field, _message), do: errors

  def media_type(item), do: item["type"] || item[:type]
  def media_size(item), do: item["size"] || item[:size]
  def media_duration(item), do: item["duration"] || item[:duration]
  def media_width(item), do: item["width"] || item[:width]
  def media_height(item), do: item["height"] || item[:height]

  def images(media), do: Enum.filter(media, &(media_type(&1) == "image"))
  def videos(media), do: Enum.filter(media, &(media_type(&1) == "video"))

  def vertical?(item) do
    width = media_width(item)
    height = media_height(item)
    is_number(width) and is_number(height) and height > width
  end

  def finish([]), do: :ok
  def finish(errors), do: {:error, Enum.reverse(errors)}
end
