defmodule Algoie.Media.Storage do
  @moduledoc """
  Storage facade for local disk and SaaS-admin-configured S3-compatible storage.

  Local files are written beneath `priv/static/uploads`; S3 objects use a
  tenant-prefixed key and AWS Signature V4 authentication.
  """

  @max_file_size 10_000_000
  @accepted_extensions ~w(.jpg .jpeg .png .gif .webp .svg)

  def max_file_size, do: @max_file_size
  def accepted_extensions, do: @accepted_extensions

  @doc """
  Copies a temporary upload file into permanent storage for `tenant` and
  returns `{:ok, %{url:, filename:, size:}}`.
  """
  def put(tenant, source_path, original_filename, content_type \\ "application/octet-stream") do
    ext = original_filename |> Path.extname() |> String.downcase()
    safe_name = slugify_filename(original_filename)
    filename = "#{Ecto.UUID.generate()}-#{safe_name}"

    settings = Algoie.PlatformStorageSettings.get()

    case settings.backend do
      "s3" ->
        if Algoie.PlatformStorageSettings.s3?(settings) do
          put_s3(settings, tenant, source_path, original_filename, filename, ext, content_type)
        else
          {:error, :s3_not_configured}
        end

      _local ->
        put_local(tenant, source_path, original_filename, filename, ext)
    end
  end

  defp put_local(tenant, source_path, original_filename, filename, ext) do
    dest_dir = upload_dir(tenant)
    File.mkdir_p!(dest_dir)

    dest_path = Path.join(dest_dir, filename)

    with :ok <- File.cp(source_path, dest_path),
         {:ok, %File.Stat{size: size}} <- File.stat(dest_path) do
      {:ok,
       %{
         url: "/uploads/#{tenant}/#{filename}",
         filename: original_filename,
         extension: ext,
         size: size
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes the file backing a stored asset `url` (best-effort, ignores
  missing files).
  """
  def delete(nil), do: :ok

  def delete(url) do
    settings = Algoie.PlatformStorageSettings.get()

    case {public_path_for(url), Algoie.Media.S3.object_key(settings, url)} do
      {path, _key} when is_binary(path) ->
        File.rm(path)

      {nil, key} when is_binary(key) ->
        if Algoie.PlatformStorageSettings.s3?(settings),
          do: Algoie.Media.S3.delete(settings, key),
          else: :ok

        Algoie.Media.S3.delete(settings, key)

      _ ->
        :ok
    end

    :ok
  end

  defp put_s3(settings, tenant, source_path, original_filename, filename, ext, content_type) do
    key = "#{tenant}/#{filename}"

    with {:ok, body} <- File.read(source_path),
         {:ok, url} <- Algoie.Media.S3.put(settings, key, body, content_type) do
      {:ok, %{url: url, filename: original_filename, extension: ext, size: byte_size(body)}}
    end
  end

  defp public_path_for("/uploads/" <> _rest = url) do
    Path.join([Application.app_dir(:algoie, "priv/static"), url])
  end

  defp public_path_for(_), do: nil

  defp upload_dir(tenant) do
    Path.join([Application.app_dir(:algoie, "priv/static"), "uploads", tenant])
  end

  defp slugify_filename(name) do
    base = name |> Path.basename() |> Path.rootname()
    ext = name |> Path.extname() |> String.downcase()

    slug =
      base
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    slug = if slug == "", do: "file", else: slug
    slug <> ext
  end
end
