defmodule Algoie.Media.S3 do
  @moduledoc false

  alias Algoie.PlatformStorageSettings

  def put(settings, key, body, content_type) do
    case request(settings, :put, key, body, content_type) do
      {:ok, _response} -> {:ok, public_url(settings, key)}
      {:error, reason} -> {:error, reason}
    end
  end

  def get(settings, key), do: request(settings, :get, key, "", nil)

  def delete(settings, key) do
    case request(settings, :delete, key, "", nil) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def public_url(settings, key) do
    case settings.public_base_url do
      value when value not in [nil, ""] ->
        String.trim_trailing(value, "/") <> "/" <> encode_key(key)

      _private_bucket ->
        "/media/s3/" <> encode_key(key)
    end
  end

  def object_key(%{backend: "s3", endpoint: endpoint} = settings, url)
      when is_binary(endpoint) and is_binary(url) do
    if String.starts_with?(url, "/media/s3/") do
      url |> String.replace_prefix("/media/s3/", "") |> URI.decode()
    else
      [settings.public_base_url, request_base_url(settings)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.find_value(fn base ->
        prefix = String.trim_trailing(base, "/") <> "/"

        if String.starts_with?(url, prefix),
          do: url |> String.replace_prefix(prefix, "") |> URI.decode()
      end)
    end
  end

  def object_key(_settings, _url), do: nil

  defp request(settings, method, key, body, content_type) do
    url = request_base_url(settings) <> "/" <> encode_key(key)
    uri = URI.parse(url)
    now = DateTime.utc_now()
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date = Calendar.strftime(now, "%Y%m%d")
    payload_hash = sha256(body)
    host = host_header(uri)

    canonical_headers =
      "host:#{host}\nx-amz-content-sha256:#{payload_hash}\nx-amz-date:#{amz_date}\n"

    signed_headers = "host;x-amz-content-sha256;x-amz-date"

    canonical_request =
      [
        method |> Atom.to_string() |> String.upcase(),
        uri.path || "/",
        "",
        canonical_headers,
        signed_headers,
        payload_hash
      ]
      |> Enum.join("\n")

    scope = "#{date}/#{settings.region}/s3/aws4_request"
    string_to_sign = "AWS4-HMAC-SHA256\n#{amz_date}\n#{scope}\n#{sha256(canonical_request)}"
    signature = signing_key(settings, date) |> hmac(string_to_sign) |> Base.encode16(case: :lower)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{settings.access_key_id}/#{scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"

    headers =
      [
        {"authorization", authorization},
        {"host", host},
        {"x-amz-content-sha256", payload_hash},
        {"x-amz-date", amz_date}
      ]
      |> maybe_content_type(content_type)

    case Req.request(
           method: method,
           url: url,
           body: body,
           headers: headers,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:s3_error, status, response_body}}

      {:error, reason} ->
        {:error, {:s3_network_error, reason}}
    end
  end

  defp request_base_url(%{path_style: true} = settings),
    do: String.trim_trailing(settings.endpoint, "/") <> "/" <> settings.bucket

  defp request_base_url(settings) do
    uri = URI.parse(settings.endpoint)

    %{uri | host: "#{settings.bucket}.#{uri.host}"}
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp signing_key(settings, date) do
    ("AWS4" <> PlatformStorageSettings.secret_access_key(settings))
    |> hmac(date)
    |> hmac(settings.region)
    |> hmac("s3")
    |> hmac("aws4_request")
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
  defp sha256(data), do: data |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp encode_key(key) do
    key
    |> String.split("/", trim: true)
    |> Enum.map_join("/", &URI.encode(&1, fn char -> URI.char_unreserved?(char) end))
  end

  defp host_header(%URI{scheme: scheme, host: host, port: port})
       when (scheme == "http" and port in [nil, 80]) or (scheme == "https" and port in [nil, 443]),
       do: host

  defp host_header(%URI{host: host, port: port}), do: "#{host}:#{port}"
  defp maybe_content_type(headers, nil), do: headers
  defp maybe_content_type(headers, value), do: [{"content-type", value} | headers]
end
