defmodule AlgoieWeb.MediaObjectController do
  use AlgoieWeb, :controller

  alias Algoie.Media.S3
  alias Algoie.PlatformStorageSettings

  def show(conn, %{"key" => key_parts}) do
    key = Enum.join(key_parts, "/")
    settings = PlatformStorageSettings.get()

    if valid_key?(key) and PlatformStorageSettings.s3?(settings) do
      case S3.get(settings, key) do
        {:ok, response} ->
          content_type = response_header(response, "content-type") || "application/octet-stream"

          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
          |> maybe_put_header("etag", response_header(response, "etag"))
          |> send_resp(200, response.body)

        {:error, _reason} ->
          send_resp(conn, 404, "Media not found")
      end
    else
      send_resp(conn, 404, "Media not found")
    end
  end

  defp valid_key?(key) do
    String.starts_with?(key, "tenant_") and
      not String.contains?(key, ["..", "\\", <<0>>])
  end

  defp response_header(response, name) do
    case Req.Response.get_header(response, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp maybe_put_header(conn, _name, nil), do: conn
  defp maybe_put_header(conn, name, value), do: put_resp_header(conn, name, value)
end
